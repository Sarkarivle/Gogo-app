const Config = require('../../models/Config');
const RazorpayProvider = require('./RazorpayProvider');
const PhonePeProvider = require('./PhonePeProvider');
const CashfreeProvider = require('./CashfreeProvider');
const GooglePlayProvider = require('./GooglePlayProvider');
const PaymentTransaction = require('../../models/PaymentTransaction');
const User = require('../../models/User');
const analyticsService = require('../analyticsService');
const revenueService = require('../revenueService');
const { normalize, phoneQuery } = require('../../utils/phoneUtils');

class PaymentService {
    static async getProvider(gatewayName) {
        const config = await Config.findOne({ key: 'payment_settings' });

        // If no config found in DB, return a dummy provider or throw a clean error
        if (!config || !config.value) {
            console.error("❌ CRITICAL: 'payment_settings' missing in MongoDB Config collection.");
            throw new Error("Payment settings not configured in database.");
        }

        const settings = config.value;
        const gateway = (gatewayName || settings.activeGateway || '').toLowerCase();

        if (!gateway) {
            throw new Error("No active payment gateway selected in settings.");
        }

        // CRITICAL FIX: Check if the specific gateway config exists before passing it
        const gatewayConfig = settings[gateway];
        if (gateway !== 'google_play' && !gatewayConfig) {
            console.error(`❌ ERROR: Configuration for gateway '${gateway}' is undefined in DB.`);
            throw new Error(`Payment gateway '${gateway}' is selected but its credentials are missing.`);
        }

        switch (gateway) {
            case 'razorpay':
                return new RazorpayProvider(gatewayConfig);
            case 'phonepe':
                return new PhonePeProvider(gatewayConfig);
            case 'cashfree':
                return new CashfreeProvider(gatewayConfig);
            case 'google_play':
                const gpConfig = await Config.findOne({ key: 'google_play_settings' });
                return new GooglePlayProvider(gpConfig ? gpConfig.value : (settings.google_play || {}));
            default:
                throw new Error(`Unsupported gateway: ${gateway}`);
        }
    }

    static async createOrder(phone, preferredGateway, overrides = {}) {
        try {
            const normalizedPhone = normalize(phone);
            const provider = await this.getProvider(preferredGateway);

            // Fetch Plan Details & Offers from Config
            const config = await Config.findOne({ key: 'payment_settings' });
            const settings = config?.value || {};

            const user = await User.findOne(phoneQuery(normalizedPhone));
            const hasUsedTrial = user?.subscription?.hasUsedTrial || false;

            let amount = overrides.amount || (hasUsedTrial ? (settings.monthlyPrice || 199) : (settings.trialPrice || 1));
            let planId = overrides.offerId || null;
            let googlePlayId = overrides.googlePlayId || null;
            let googlePlaySubId = overrides.googlePlaySubId || null;
            let duration = overrides.duration || (amount < 10 ? 1 : 30);

            // OVERRIDE IF WIN-BACK OFFER IS APPLICABLE (Only if no explicit amount override)
            if (!overrides.amount && hasUsedTrial && !user.isPremium) {
                const now = new Date();
                const trialEnd = new Date(user.subscription?.trialEndDate || user.subscription?.lastPaymentDate);
                const daysSinceTrial = Math.floor((now - trialEnd) / (1000 * 60 * 60 * 24));

                if (daysSinceTrial >= (settings.offerStartDay || 1) &&
                    daysSinceTrial <= (settings.offerEndDay || 7) &&
                    settings.isOfferEnabled) {

                    amount = settings.offerPrice || 99;
                    planId = settings.offerPlanId;
                }
            }

            const orderData = await provider.createOrder({
                phone: normalizedPhone,
                amount,
                isSubscription: true, // This is now always true for Autopay
                isTrial: amount < 10,
                overridePlanId: planId,
                productId: googlePlayId,
                googlePlaySubId: googlePlaySubId
            });

            if (orderData.success && orderData.orderId) {
                await PaymentTransaction.create({
                    orderId: orderData.orderId,
                    userPhone: normalizedPhone,
                    gateway: orderData.gateway,
                    amount: amount,
                    status: 'PENDING',
                    metadata: { ...orderData, duration, offerId: planId }
                });
            }
            return orderData;
        } catch (error) {
            console.error("Order Creation Failed:", error.message);
            return { success: false, message: error.message };
        }
    }

    // ... baaki functions (verifyPayment, processWebhook, etc.) wahi rahenge
    static async _updateUserSubscription(phone, transaction, method, io) {
        const now = new Date();
        const normalizedPhone = normalize(phone);

        // LOGIC: If upfront setup fee is below 10, it's a trial
        const isTrial = transaction.amount < 10;

        // SIMPLE FIX: Trust the Payment Provider's data first
        // Priority: next_billing_at > current_period_end > start_at > fallback logic
        let newExpiry;
        const providerNextBill = transaction.next_billing_at || transaction.current_period_end || transaction.start_at;

        if (providerNextBill) {
            newExpiry = new Date(providerNextBill * 1000);
        } else if (transaction.metadata?.expiryTimeMillis) {
            // Google Play specific from verification
            newExpiry = new Date(parseInt(transaction.metadata.expiryTimeMillis));
        } else {
            // Fallback: If provider gives nothing, use duration
            const durationDays = transaction.metadata?.duration || (isTrial ? 1 : 30);
            newExpiry = new Date(now.getTime() + (durationDays * 24 * 60 * 60 * 1000));
        }

        const planName = isTrial ? `₹${transaction.amount || 1} Trial Gold` : 'Monthly Gold';

        const transactionId = transaction.gatewayTransactionId || transaction.paymentId || transaction.orderId;

        // 1. DEDUPLICATION CHECK: Ensure we don't add the same transaction twice
        const alreadyProcessed = await User.findOne({
            ...phoneQuery(normalizedPhone),
            'paymentHistory.orderId': transactionId
        });

        if (alreadyProcessed) {
            // WEBHOOK UPDATE: If transaction exists but expiry is newer, update it (Handles Razorpay race condition)
            if (transaction.current_period_end) {
                const webhookExpiry = new Date(transaction.current_period_end * 1000);
                const currentExpiry = alreadyProcessed.premiumExpiry;

                if (!currentExpiry || webhookExpiry > currentExpiry) {
                    console.log(`📡 Updating expiry from Webhook for ${normalizedPhone}: ${webhookExpiry}`);
                    await User.updateOne(phoneQuery(normalizedPhone), {
                        $set: {
                            premiumExpiry: webhookExpiry,
                            'subscription.nextBillingDate': webhookExpiry,
                            'subscription.status': isTrial ? 'trial_active' : 'active'
                        }
                    });
                }
            }
            console.log(`⚠️ Skip: Transaction ${transactionId} already processed for ${phone}`);
            return alreadyProcessed;
        }

        const updateFields = {
            isPremium: true,
            premiumExpiry: newExpiry,
            premiumPlan: planName,
            'subscription.status': isTrial ? 'trial_active' : 'active',
            'subscription.hasUsedTrial': true,
            'subscription.startDate': now,
            'subscription.nextBillingDate': newExpiry,
            'subscription.lastPaymentDate': now,
            'subscription.paymentMethod': method || 'UPI',
            'subscription.autoRenew': true,
            'subscription.lastAmountPaid': transaction.amount || 0
        };

        if (transaction.orderId && (transaction.orderId.startsWith('sub_') || transaction.orderId.startsWith('S_'))) {
            updateFields['subscription.id'] = transaction.orderId;
        } else if (transaction.gateway === 'google_play') {
            // For Google Play, use the actual order ID (GPA.xxx) if available in metadata
            updateFields['subscription.id'] = transaction.metadata?.orderId || transaction.orderId;
        }

        const updatedUser = await User.findOneAndUpdate(
            phoneQuery(normalizedPhone),
            {
                $set: updateFields,
                $inc: { 'subscription.totalAmountPaid': transaction.amount || 0 },
                $push: {
                    paymentHistory: {
                        orderId: transactionId,
                        amount: transaction.amount || 0,
                        status: 'SUCCESS',
                        method: method || 'UPI',
                        timestamp: now
                    }
                }
            },
            { new: true }
        );

        if (io) {
            io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', {
                isPremium: true,
                status: isTrial ? 'trial_active' : 'active',
                message: isTrial ? "Trial Activated! 🎁" : "Premium Activated! ✨"
            });
            // Notify admin dashboard
            io.to('admin').emit('admin_live_event', {
                type: 'PAYMENT_SUCCESS',
                label: `${isTrial ? 'Trial' : 'Premium'} Success: ₹${transaction.amount}`,
                phone: normalizedPhone,
                gateway: transaction.gateway || 'razorpay'
            });
        }

        analyticsService.trackPremiumUpgrade(normalizedPhone);
        revenueService.trackPaymentEvent('PAYMENT_SUCCESS', { userPhone: normalizedPhone, amount: transaction.amount || 0, gateway: transaction.gateway || 'razorpay' });
        return updatedUser;
    }

    static async syncWithProvider(phone, io) {
        try {
            const normalizedPhone = normalize(phone);
            const user = await User.findOne(phoneQuery(normalizedPhone));
            if (!user) throw new Error("User not found");

            const gateway = user.subscription?.paymentMethod?.toLowerCase().includes('google') ? 'google_play' : 'razorpay';
            const provider = await this.getProvider(gateway);
            const subId = user.subscription?.id;

            let updatedData = {};

            if (gateway === 'razorpay' && subId) {
                const subDetails = await provider.client.subscriptions.fetch(subId);
                let amount = 0;
                try {
                    const plan = await provider.client.plans.fetch(subDetails.plan_id);
                    amount = plan.item.amount / 100;
                } catch (e) {}

                // Status Mapping for Razorpay
                let status = 'expired';
                if (subDetails.status === 'active') status = 'active';
                else if (subDetails.status === 'authenticated') status = 'trial_active';
                else if (subDetails.status === 'cancelled') status = 'cancelled';

                // SIMPLE LOGIC: Razorpay provides 'next_billing_at' as the source of truth
                const nextBillTimestamp = subDetails.next_billing_at || subDetails.current_end || subDetails.start_at;
                const nextBill = nextBillTimestamp ? new Date(nextBillTimestamp * 1000) : null;

                updatedData = {
                    status: status,
                    nextBillingDate: nextBill,
                    autoRenew: ['active', 'authenticated', 'pending'].includes(subDetails.status),
                    amount: amount
                };
            } else if (gateway === 'google_play') {
                const purchaseToken = user.subscription?.id || user.paymentHistory?.find(p => p.method === 'Google Play')?.gatewayTransactionId || user.paymentHistory?.find(p => p.method === 'Google Play')?.orderId;
                const productId = user.subscription?.planId || 'gogo_monthy_199';

                if (purchaseToken) {
                    const verification = await provider.verifyPayment({ purchaseToken, productId });
                    if (verification.success && verification.expiryTimeMillis) {
                        const expiry = parseInt(verification.expiryTimeMillis);
                        updatedData = {
                            status: (expiry > Date.now()) ? 'active' : 'expired',
                            nextBillingDate: new Date(expiry),
                            autoRenew: verification.autoRenewing !== undefined ? verification.autoRenewing : true,
                            amount: verification.amount || 0
                        };
                    }
                }
            }

            if (Object.keys(updatedData).length > 0) {
                user.subscription.status = updatedData.status;
                if (updatedData.nextBillingDate) {
                    user.subscription.nextBillingDate = updatedData.nextBillingDate;
                    user.premiumExpiry = updatedData.nextBillingDate;
                }
                user.subscription.autoRenew = updatedData.autoRenew;
                user.subscription.lastAmountPaid = updatedData.amount || 0;
                user.isPremium = updatedData.status === 'active' || updatedData.status === 'trial_active';

                await user.save();

                if (io) {
                    io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', {
                        isPremium: user.isPremium,
                        status: user.subscription.status,
                        message: "Subscription Synchronized 🔄"
                    });
                }
            }

            return { success: true, user, lastPaidAmount: updatedData.amount };
        } catch (e) {
            console.error("SyncWithProvider Error:", e.message);
            throw e;
        }
    }

    static async revokeSubscription(phone, status = 'cancelled') {
        const normalizedPhone = normalize(phone);
        // Note: We don't necessarily set isPremium=false immediately on cancellation
        // but we update the status so the system knows not to renew.
        // If status is 'expired', then we revoke access.
        const updateFields = {
            'subscription.status': status,
            'subscription.autoRenew': false
        };

        if (status === 'expired') {
            updateFields.isPremium = false;
        }

        return await User.findOneAndUpdate(
            phoneQuery(normalizedPhone),
            { $set: updateFields },
            { new: true }
        );
    }

    static async syncUserStatus(phone) {
        const normalizedPhone = normalize(phone);
        const user = await User.findOne(phoneQuery(normalizedPhone));
        if (!user) return { isPremium: false, status: 'none' };

        const config = await Config.findOne({ key: 'payment_settings' });
        const settings = config?.value || {};

        const now = new Date();
        let offerData = null;

        // CHECK FOR WIN-BACK OFFER ELIGIBILITY
        if (!user.isPremium && user.subscription?.hasUsedTrial) {
            const trialEnd = new Date(user.subscription.trialEndDate || user.subscription.lastPaymentDate);
            const daysSinceTrial = Math.floor((now - trialEnd) / (1000 * 60 * 60 * 24));

            const offerStart = settings.offerStartDay || 1;
            const offerEnd = settings.offerEndDay || 7;

            if (daysSinceTrial >= offerStart && daysSinceTrial <= offerEnd && settings.isOfferEnabled) {
                offerData = {
                    price: settings.offerPrice || 99,
                    planId: settings.offerPlanId,
                    title: "Special Comeback Offer! 🎁",
                    message: `Get full access for just ₹${settings.offerPrice}! Limited time only.`
                };
            }
        }

        // Real logic: Check if expiry has passed
        if (user.isPremium && user.premiumExpiry && user.premiumExpiry < now) {
            user.isPremium = false;
            user.subscription.status = 'expired';
            await user.save();
        }

        return {
            isPremium: user.isPremium,
            status: user.subscription?.status || 'none',
            expiry: user.premiumExpiry,
            premiumPlan: user.premiumPlan,
            subscription: user.subscription,
            paymentHistory: (user.paymentHistory || []).slice(-10), // Include recent history for real-time update
            offer: offerData
        };
    }

    static async cancelSubscription(phone) {
        const normalizedPhone = normalize(phone);
        const user = await User.findOne(phoneQuery(normalizedPhone));
        if (!user || !user.subscription?.id) throw new Error("No active subscription found");

        const provider = await this.getProvider('razorpay');

        try {
            // 1. Fetch current status from Razorpay
            const subDetails = await provider.client.subscriptions.fetch(user.subscription.id);

            // 2. If already cancelled on Razorpay, just sync our DB and return success
            if (subDetails.status === 'cancelled') {
                user.subscription.status = 'cancelled';
                user.subscription.autoRenew = false;
                await user.save();
                return { success: true, message: "Subscription was already cancelled." };
            }

            // 3. Decide cancellation method
            const cancelImmediately = (
                subDetails.status === 'authenticated' ||
                subDetails.status === 'created' ||
                (subDetails.paid_count === 0)
            );

            try {
                await provider.client.subscriptions.cancel(user.subscription.id, !cancelImmediately);
            } catch (innerErr) {
                // Razorpay error structure check
                const innerDesc = (innerErr.error?.description || innerErr.description || "").toLowerCase();
                // If it's already cancelled or has status issue, treat as success
                if (innerDesc.includes('not cancellable') || innerDesc.includes('already cancelled') || innerDesc.includes('no billing cycle')) {
                    // fall through to DB update
                } else {
                    throw innerErr;
                }
            }

            // 4. Update local DB
            user.subscription.status = 'cancelled';
            user.subscription.autoRenew = false;
            await user.save();

            return {
                success: true,
                message: "Subscription successfully cancelled."
            };
        } catch (err) {
            console.error("Cancel Error Logic Trace:", err);

            // IMPROVED ERROR CATCHING:
            // Razorpay returns error nested in 'error' object or sometimes as top level description
            const errorDesc = (err.error?.description || err.description || err.message || "").toLowerCase();

            if (errorDesc.includes('not cancellable') || errorDesc.includes('already cancelled') || errorDesc.includes('no billing cycle') || errorDesc.includes('cancelled status')) {
                 if (user) {
                    user.subscription.status = 'cancelled';
                    user.subscription.autoRenew = false;
                    await user.save();
                 }
                 return { success: true, message: "Subscription auto-pay disabled." };
            }
            throw new Error(err.message || "Failed to cancel subscription");
        }
    }

    static async verifyPayment(phone, paymentData, io) {
        try {
            const normalizedPhone = normalize(phone);
            const gateway = paymentData.gateway || 'razorpay';
            const provider = await this.getProvider(gateway);

            const verification = await provider.verifyPayment(paymentData);
            if (verification.success) {
                let transaction;
                const orderId = paymentData.orderId || paymentData.razorpay_subscription_id || paymentData.merchantTransactionId || verification.transactionId;

                // NEW: Fetch latest subscription details directly from Razorpay to get the EXACT expiry date
                let currentPeriodEnd = null;
                if (gateway === 'razorpay' && (paymentData.razorpay_subscription_id || orderId.startsWith('sub_'))) {
                    try {
                        const subId = paymentData.razorpay_subscription_id || orderId;
                        const subDetails = await provider.client.subscriptions.fetch(subId);
                        if (subDetails) {
                            // Priority: next_billing_at > current_end > start_at
                            currentPeriodEnd = subDetails.next_billing_at || subDetails.current_end || subDetails.start_at;
                        }
                    } catch (err) { console.error("Error fetching sub details:", err); }
                }

                // GOOGLE PLAY SYNC: Use data returned from verification
                if (gateway === 'google_play' && verification.expiryTimeMillis) {
                    currentPeriodEnd = Math.floor(verification.expiryTimeMillis / 1000);
                }

                transaction = await PaymentTransaction.findOneAndUpdate(
                    { orderId, status: 'PENDING' },
                    {
                        status: 'SUCCESS',
                        gatewayTransactionId: verification.transactionId,
                        paymentMethod: paymentData.method || (gateway === 'google_play' ? 'Google Play' : 'UPI'),
                        current_period_end: currentPeriodEnd,
                        metadata: verification.raw || {}
                    },
                    { new: true }
                );

                if (!transaction && gateway === 'google_play') {
                    // Fallback for direct play store purchases without pre-created order
                    // Use verification amount if available, otherwise fallback to 0 instead of hardcoded 199
                    let amount = verification.amount || paymentData.amount || 0;
                    transaction = await PaymentTransaction.create({
                        orderId, userPhone: normalizedPhone, gateway: 'google_play',
                        amount, status: 'SUCCESS', gatewayTransactionId: verification.transactionId,
                        paymentMethod: 'Google Play',
                        current_period_end: currentPeriodEnd,
                        metadata: verification.raw || {}
                    });
                }

                if (!transaction) {
                    const alreadyDone = await PaymentTransaction.findOne({ orderId, status: 'SUCCESS' });
                    if (alreadyDone) return { success: true, user: await User.findOne(phoneQuery(normalizedPhone)) };
                    throw new Error("Invalid or duplicate transaction");
                }

                const updatedUser = await this._updateUserSubscription(normalizedPhone, transaction, transaction.paymentMethod, io);
                return { success: true, user: updatedUser };
            }
            return { success: false, message: "Verification failed" };
        } catch (e) { return { success: false, message: e.message }; }
    }

    static async processWebhook(gateway, payload, signature, rawBody, io) {
        try {
            const provider = await this.getProvider(gateway);
            const result = await provider.handleWebhook(payload, signature, rawBody);

            if (result.status === 'IGNORE') return { success: true };

            let phone = result.userPhone;
            let transaction = null;

            // GOOGLE PLAY SPECIAL HANDLING: Find user by purchaseToken or existing transaction
            if (gateway === 'google_play' && result.purchaseToken) {
                const existingTx = await PaymentTransaction.findOne({
                    gatewayTransactionId: result.purchaseToken
                });
                if (existingTx) {
                    phone = existingTx.userPhone;
                    transaction = existingTx;
                } else {
                    // Try to find user directly from history if token was saved there
                    const userWithToken = await User.findOne({ 'paymentHistory.orderId': result.purchaseToken });
                    if (userWithToken) phone = userWithToken.phone;
                }
            }

            if (!phone || phone === 'UNKNOWN') {
                console.log(`ℹ️ Webhook ${gateway} received but user not identified yet.`);
                return { success: true };
            }

            const normalizedPhone = normalize(phone);

            // ENSURE TRANSACTION OBJECT HAS LATEST DATA FROM WEBHOOK
            const orderId = result.orderId || (gateway === 'google_play' ? result.purchaseToken : null);

            if (!transaction && orderId) {
                transaction = await PaymentTransaction.findOne({ orderId: orderId });
            }

            if (!transaction) {
                transaction = await PaymentTransaction.create({
                    orderId: orderId || `wh_${Date.now()}`,
                    userPhone: normalizedPhone, gateway,
                    amount: result.amount || 0, status: 'SUCCESS',
                    gatewayTransactionId: result.paymentId || result.purchaseToken,
                    current_period_end: result.next_billing_at || result.current_period_end || result.start_at
                });
            } else {
                transaction.status = 'SUCCESS';
                if (result.paymentId) transaction.gatewayTransactionId = result.paymentId;
                const bestDate = result.next_billing_at || result.current_period_end || result.start_at;
                if (bestDate) transaction.current_period_end = bestDate;
                await transaction.save();
            }

            // USER STATE MACHINE HANDLING
            switch (result.status) {
                case 'TRIAL_SUCCESS':
                case 'RENEWAL_SUCCESS':
                case 'SUCCESS':
                    // If it's Google Play, sync once to get exact expiry and amount
                    if (gateway === 'google_play') {
                        await this.syncWithProvider(normalizedPhone, io).catch(e => console.error("Webhook Sync Error:", e));
                    } else {
                        await this._updateUserSubscription(normalizedPhone, result, 'UPI', io);
                    }
                    break;

                case 'CANCELLED':
                    await User.findOneAndUpdate(phoneQuery(normalizedPhone), {
                        $set: { 'subscription.autoRenew': false, 'subscription.status': 'cancelled' }
                    });
                    if (io) {
                        io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { status: 'cancelled', message: "Auto-pay disabled", type: 'warning' });
                        io.to('admin').emit('admin_live_event', { type: 'SUB_CANCELLED', label: 'Subscription Cancelled', phone: normalizedPhone });
                    }
                    break;

                case 'PAYMENT_FAILED':
                    await User.findOneAndUpdate(phoneQuery(normalizedPhone), {
                        $set: { 'subscription.status': 'payment_failed' }
                    });
                    if (io) {
                        io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { status: 'payment_failed', message: "Payment Failed ❌", type: 'warning' });
                        io.to('admin').emit('admin_live_event', { type: 'PAYMENT_FAILED', label: 'Payment Failed', phone: normalizedPhone });
                    }
                    break;

                case 'EXPIRED':
                    await this.revokeSubscription(normalizedPhone, 'expired');
                    if (io) {
                        io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { isPremium: false, status: 'expired', message: "Membership Expired", type: 'warning' });
                        io.to('admin').emit('admin_live_event', { type: 'SUB_EXPIRED', label: 'Subscription Expired', phone: normalizedPhone });
                    }
                    break;
            }

            return { success: true };
        } catch (e) {
            console.error("Webhook Processing Error:", e.message);
            return { success: false };
        }
    }
}

module.exports = PaymentService;
