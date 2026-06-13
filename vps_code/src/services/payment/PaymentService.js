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

            const offerConfig = await Config.findOne({ key: 'special_offers' });
            const offers = offerConfig?.value?.offers || [];

            const user = await User.findOne(phoneQuery(normalizedPhone));
            const hasUsedTrial = user?.subscription?.hasUsedTrial || false;

            // NEW LOGIC: New User -> 1st Offer (Trial/Welcome), Old User -> 3rd Offer (Standard/Premium)
            let selectedOffer;
            if (offers && offers.length > 0) {
                if (!hasUsedTrial) {
                    selectedOffer = offers[0]; // First Offer
                } else {
                    selectedOffer = offers[2] || offers[0]; // Third Offer (fallback to first if not exists)
                }
            }

            let amount = overrides.amount || selectedOffer?.price || 199;
            let planId = overrides.offerId || selectedOffer?.id || selectedOffer?.rzpPlanId;

            // CRITICAL: Ensure we have a planId before proceeding
            if (!planId) {
                console.error("❌ ERROR: No planId found for order creation. Check 'special_offers' config.");
                throw new Error("Unable to identify payment plan. Please contact support.");
            }

            let duration = overrides.duration || selectedOffer?.duration || 30;

            let googlePlayId = overrides.googlePlayId || (amount < 10 ? null : selectedOffer?.googlePlayId);
            let googlePlaySubId = overrides.googlePlaySubId || (amount < 10 ? null : selectedOffer?.googlePlaySubId);

            const orderData = await provider.createOrder({
                phone: normalizedPhone,
                amount,
                isSubscription: true,
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
                    metadata: { ...orderData, duration, offerId: planId, isFirstTime: !hasUsedTrial }
                });
            }
            return orderData;
        } catch (error) {
            console.error("Order Creation Failed:", error.message || error);
            return { success: false, message: error.message || String(error) };
        }
    }

    // ... baaki functions (verifyPayment, processWebhook, etc.) wahi rahenge
    static async _updateUserSubscription(phone, transaction, method, io) {
        const now = new Date();
        const normalizedPhone = normalize(phone);

        // LOGIC: If upfront setup fee is below 10, it's a trial
        const isTrial = transaction.amount < 10;

        // DYNAMIC PLAN NAME: Fetch from Special Offers config
        let planName = isTrial ? `Trial Gold` : 'Premium Gold';
        try {
            const offerConfig = await Config.findOne({ key: 'special_offers' });
            const offers = offerConfig?.value?.offers || [];
            const productId = transaction.metadata?.productId || transaction.metadata?.offerId;
            // Match by ProductId, SubId, ID or Price
            const matchedOffer = offers.find(o =>
                (productId && (o.googlePlayId === productId || o.googlePlaySubId === productId || o.id === productId)) ||
                (o.price == transaction.amount)
            );
            if (matchedOffer) planName = matchedOffer.name;
        } catch (e) { console.error("Plan name fetch error:", e); }

        // GATEWAY PRIORITY LOGIC: Expiry MUST come from the gateway
        let newExpiry;
        const providerNextBill = transaction.current_period_end || transaction.next_billing_at || transaction.start_at;

        if (providerNextBill) {
            newExpiry = new Date(providerNextBill * 1000);
        } else if (transaction.metadata?.expiryTimeMillis) {
            newExpiry = new Date(parseInt(transaction.metadata.expiryTimeMillis));
        } else {
            // FALLBACK: Gateway delay scenario
            console.warn(`📡 Gateway expiry missing for ${normalizedPhone}, using provider metadata.`);
            const durationDays = transaction.metadata?.duration || (isTrial ? 1 : 30);
            newExpiry = new Date(now.getTime() + (durationDays * 24 * 60 * 60 * 1000));
        }

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
                            premiumPlan: planName, // Update plan name too in case it changed
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
            'subscription.lastAmountPaid': transaction.amount || 0,
            'subscription.planId': transaction.metadata?.productId || transaction.metadata?.offerId
        };

        if (transaction.orderId && (transaction.orderId.startsWith('sub_') || transaction.orderId.startsWith('S_'))) {
            updateFields['subscription.id'] = transaction.orderId;
        } else if (transaction.gateway === 'google_play') {
            // CRITICAL FIX: For Google Play, 'subscription.id' MUST be the purchaseToken for syncing
            // We store the GPA.xxx orderId in metadata
            updateFields['subscription.id'] = transaction.gatewayTransactionId || transaction.metadata?.purchaseToken;
            if (transaction.metadata?.orderId) {
                updateFields['subscription.googleOrderId'] = transaction.metadata.orderId;
            }
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
                // Removed toast message
            });
            // Notify admin dashboard
            io.to('admin').emit('admin_live_event', {
                type: 'PAYMENT_SUCCESS',
                label: `${isTrial ? 'Trial' : 'Premium'} Success: ₹${transaction.amount}`,
                phone: normalizedPhone,
                gateway: transaction.gateway || 'razorpay'
            });
        }

        analyticsService.trackPremiumUpgrade(normalizedPhone, {
            amount: transaction.amount || 0,
            currency: 'INR',
            planId: transaction.metadata?.productId || transaction.metadata?.offerId
        });
        revenueService.trackPaymentEvent('PAYMENT_SUCCESS', { userPhone: normalizedPhone, amount: transaction.amount || 0, gateway: transaction.gateway || 'razorpay' });
        return updatedUser;
    }

    static async syncWithProvider(phone, io) {
        try {
            const normalizedPhone = normalize(phone);
            const user = await User.findOne(phoneQuery(normalizedPhone));
            if (!user) throw new Error("User not found");

            const subId = user.subscription?.id;
            // CRITICAL: If no subscription ID, nothing to sync with Gateway
            if (!subId) {
                return { success: true, user, message: "No active subscription ID to sync." };
            }

            // SOURCE OF TRUTH: Detect Gateway
            const gateway = (user.subscription?.paymentMethod?.toLowerCase().includes('google') || subId.startsWith('GPA.')) ? 'google_play' : 'razorpay';
            const provider = await this.getProvider(gateway);

            let updatedData = {};

            if (gateway === 'razorpay') {
                // Razorpay Subscriptions start with 'sub_'
                if (subId.startsWith('sub_')) {
                    const subDetails = await provider.client.subscriptions.fetch(subId);

                    let status = 'expired';
                    if (['active', 'authenticated'].includes(subDetails.status)) status = 'active';
                    if (subDetails.status === 'cancelled') status = 'cancelled';

                    const nextBillTimestamp = subDetails.next_billing_at || subDetails.current_end || subDetails.start_at;
                    updatedData = {
                        status,
                        nextBillingDate: nextBillTimestamp ? new Date(nextBillTimestamp * 1000) : null,
                        autoRenew: !['cancelled', 'expired'].includes(subDetails.status)
                    };
                }
            } else if (gateway === 'google_play') {
                let purchaseToken = subId;
                let productId = user.subscription?.planId || 'gogo_monthly_199';

                // If subId is an Order ID (GPA.), try to find the real purchaseToken from transactions
                if (purchaseToken.startsWith('GPA.')) {
                    const tx = await PaymentTransaction.findOne({
                        userPhone: normalizedPhone,
                        gateway: 'google_play',
                        status: 'SUCCESS'
                    }).sort({ createdAt: -1 });
                    if (tx) purchaseToken = tx.gatewayTransactionId || tx.metadata?.purchaseToken;
                }

                // Only sync if we have a real token (Google Play tokens don't start with GPA.)
                if (purchaseToken && !purchaseToken.startsWith('GPA.')) {
                    const verification = await provider.verifyPayment({ purchaseToken, productId });
                    if (verification.success && verification.expiryTimeMillis) {
                        const expiry = parseInt(verification.expiryTimeMillis);
                        updatedData = {
                            status: (expiry > Date.now()) ? 'active' : 'expired',
                            nextBillingDate: new Date(expiry),
                            autoRenew: verification.autoRenewing || false
                        };
                    }
                }
            }

            // UPDATE DATABASE: Only if we got fresh data from Gateway
            if (Object.keys(updatedData).length > 0) {
                const isPremium = updatedData.status === 'active' || (updatedData.nextBillingDate && updatedData.nextBillingDate > new Date());

                const updatedUser = await User.findOneAndUpdate(
                    phoneQuery(normalizedPhone),
                    {
                        $set: {
                            isPremium,
                            premiumExpiry: updatedData.nextBillingDate,
                            'subscription.status': updatedData.status,
                            'subscription.nextBillingDate': updatedData.nextBillingDate,
                            'subscription.autoRenew': updatedData.autoRenew
                        }
                    },
                    { new: true }
                );

                if (io) {
                    // REAL-TIME SOCKET EMIT: Send all critical data to the app instantly
                    io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', {
                        isPremium,
                        status: updatedData.status,
                        expiry: updatedData.nextBillingDate,
                        autoRenew: updatedData.autoRenew,
                        subscription: updatedUser.subscription,
                        message: null // Background sync should be silent
                    });
                }
                return { success: true, user: updatedUser };
            }

            return { success: true, user: await User.findOne(phoneQuery(normalizedPhone)) };
        } catch (error) {
            // Log the specific error but don't crash the whole status check
            console.error(`📡 Provider Sync Error (${phone}):`, error.message);
            return { success: false, message: error.message };
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

        const offerConfig = await Config.findOne({ key: 'special_offers' });
        const featuredOffer = offerConfig?.value?.offers?.[0];

        const now = new Date();
        let offerData = null;

        // SINGLE OFFER SYSTEM: Return either Trial or Featured Offer for non-premium users
        if (!user.isPremium) {
            if (!user.subscription?.hasUsedTrial && settings.trialPrice < 10) {
                offerData = {
                    price: settings.trialPrice || 1,
                    duration: settings.trialDuration || 1,
                    title: "Special Trial Offer! 🎁",
                    message: `Get full access for just ₹${settings.trialPrice}! Limited time trial.`,
                    isTrial: true
                };
            } else if (featuredOffer) {
                offerData = {
                    price: featuredOffer.price,
                    planId: featuredOffer.id,
                    title: featuredOffer.name || "Exclusive Offer! ✨",
                    message: `Upgrade to Gold for just ₹${featuredOffer.price}. Limited time.`,
                    isTrial: false,
                    duration: featuredOffer.duration
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

                const existingTransaction = await PaymentTransaction.findOne({ orderId, status: 'PENDING' });

                if (existingTransaction) {
                    transaction = await PaymentTransaction.findOneAndUpdate(
                        { _id: existingTransaction._id },
                        {
                            status: 'SUCCESS',
                            gatewayTransactionId: verification.transactionId,
                            paymentMethod: paymentData.method || (gateway === 'google_play' ? 'Google Play' : 'UPI'),
                            current_period_end: currentPeriodEnd,
                            metadata: { ...existingTransaction.metadata, ...verification.raw, productId: paymentData.productId || existingTransaction.metadata?.productId }
                        },
                        { new: true }
                    );
                }

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

            // GOOGLE PLAY SPECIAL HANDLING: Find user by purchaseToken
            if (gateway === 'google_play' && result.purchaseToken) {
                console.log(`🔍 Webhook: Searching for user with token: ${result.purchaseToken.substring(0, 20)}...`);

                // 1. Try Transactions
                const existingTx = await PaymentTransaction.findOne({
                    $or: [{ orderId: result.purchaseToken }, { gatewayTransactionId: result.purchaseToken }]
                });

                if (existingTx) {
                    phone = existingTx.userPhone;
                    transaction = existingTx;
                    console.log(`✅ Found user via Transaction: ${phone}`);
                } else {
                    // 2. Try User Payment History
                    const userWithToken = await User.findOne({
                        $or: [
                            { 'subscription.id': result.purchaseToken },
                            { 'paymentHistory.orderId': result.purchaseToken }
                        ]
                    });
                    if (userWithToken) {
                        phone = userWithToken.phone;
                        console.log(`✅ Found user via Payment History: ${phone}`);
                    }
                }
            }

            if (!phone || phone === 'UNKNOWN') {
                console.log(`ℹ️ Webhook ${gateway} received but user not identified yet.`);
                return { success: true };
            }

            const normalizedPhone = normalize(phone);
            console.log(`📡 Processing ${result.status} for ${normalizedPhone}`);

            // ENSURE TRANSACTION OBJECT HAS LATEST DATA FROM WEBHOOK
            const orderId = result.orderId || (gateway === 'google_play' ? result.purchaseToken : null);

            if (!transaction && orderId) {
                transaction = await PaymentTransaction.findOne({ orderId: orderId });
            }

            if (!transaction) {
                let amount = result.amount || 0;

                // For Google Play renewals, RTDN doesn't give amount. Try to fetch from config.
                if (gateway === 'google_play' && amount === 0) {
                    try {
                        const offerConfig = await Config.findOne({ key: 'special_offers' });
                        const offers = offerConfig?.value?.offers || [];
                        const productId = result.productId || (await User.findOne(phoneQuery(normalizedPhone)))?.subscription?.planId;
                        const matchedOffer = offers.find(o => o.googlePlayId === productId || o.googlePlaySubId === productId);
                        if (matchedOffer) {
                            amount = matchedOffer.price;
                        } else {
                            const payConfig = await Config.findOne({ key: 'payment_settings' });
                            amount = payConfig?.value?.monthlyPrice || 199;
                        }
                    } catch (err) { console.error("Error fetching amount for webhook:", err); }
                }

                transaction = await PaymentTransaction.create({
                    orderId: orderId || `wh_${Date.now()}`,
                    userPhone: normalizedPhone, gateway,
                    amount: amount, status: 'SUCCESS',
                    gatewayTransactionId: result.paymentId || result.purchaseToken,
                    current_period_end: result.next_billing_at || result.current_period_end || result.start_at,
                    metadata: { productId: result.productId }
                });
            } else {
                transaction.status = 'SUCCESS';
                if (result.paymentId) transaction.gatewayTransactionId = result.paymentId;
                const bestDate = result.next_billing_at || result.current_period_end || result.start_at;
                if (bestDate) transaction.current_period_end = bestDate;
                if (result.productId) {
                    transaction.metadata = { ...transaction.metadata, productId: result.productId };
                }
                await transaction.save();
            }

            // USER STATE MACHINE HANDLING
            console.log(`🚀 Executing logic for event: ${result.event} on user: ${normalizedPhone}`);

            // UNIVERSAL RULE: For any Google Play event, always do a fresh provider sync to get current truth
            if (gateway === 'google_play') {
                await this.syncWithProvider(normalizedPhone, io).catch(e => console.error("Webhook Sync Error:", e));
            } else {
                // For Razorpay or others, we can use specific handlers
                switch (result.status) {
                    case 'SUCCESS':
                        await this._updateUserSubscription(normalizedPhone, result, 'UPI', io);
                        break;
                    case 'CANCELLED':
                        await User.updateOne(phoneQuery(normalizedPhone), {
                            $set: { 'subscription.autoRenew': false, 'subscription.status': 'cancelled' }
                        });
                        if (io) io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { status: 'cancelled', message: "Auto-pay disabled", type: 'warning' });
                        break;
                    case 'EXPIRED':
                        await this.revokeSubscription(normalizedPhone, 'expired');
                        if (io) io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { isPremium: false, status: 'expired', message: "Membership Expired", type: 'warning' });
                        break;
                }
            }

            return { success: true };

            return { success: true };
        } catch (e) {
            console.error("Webhook Processing Error:", e.message);
            return { success: false };
        }
    }
}

module.exports = PaymentService;
