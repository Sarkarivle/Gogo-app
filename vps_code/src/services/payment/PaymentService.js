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

    static async createOrder(phone, preferredGateway) {
        try {
            const normalizedPhone = normalize(phone);
            const provider = await this.getProvider(preferredGateway);

            // Fetch Plan Details & Offers from Config
            const config = await Config.findOne({ key: 'payment_settings' });
            const settings = config?.value || {};

            const user = await User.findOne(phoneQuery(normalizedPhone));
            const hasUsedTrial = user?.subscription?.hasUsedTrial || false;

            let amount = hasUsedTrial ? (settings.monthlyPrice || 199) : (settings.trialPrice || 1);
            let planId = null;

            // OVERRIDE IF WIN-BACK OFFER IS APPLICABLE
            if (hasUsedTrial && !user.isPremium) {
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
                isSubscription: true,
                isTrial: !hasUsedTrial,
                overridePlanId: planId // Pass specific plan ID if needed
            });

            if (orderData.success && orderData.orderId) {
                await PaymentTransaction.create({
                    orderId: orderData.orderId,
                    userPhone: normalizedPhone,
                    gateway: orderData.gateway,
                    amount: amount,
                    status: 'PENDING',
                    metadata: orderData
                });
            }
            return orderData;
        } catch (error) {
            console.error("Order Creation Failed:", error.message);
            return { success: false, message: error.message };
        }
    }

    // ... baaki functions (verifyPayment, processWebhook, etc.) wahi rahenge
    static async _updateUserSubscription(phone, transaction, method) {
        const now = new Date();
        const normalizedPhone = normalize(phone);

        // LOGIC: If upfront setup fee is below 10, it's a trial
        const isTrial = transaction.amount < 10;

        // Use exact expiry from Razorpay if available, otherwise calculate fallback
        let newExpiry;
        if (transaction.current_period_end) {
            newExpiry = new Date(transaction.current_period_end * 1000);
        } else {
            const durationHours = isTrial ? 24 : (30 * 24);
            const user = await User.findOne(phoneQuery(normalizedPhone));
            let baseDate = (user && user.premiumExpiry && user.premiumExpiry > now) ? user.premiumExpiry : now;
            newExpiry = new Date(baseDate.getTime() + (durationHours * 60 * 60 * 1000));
        }

        const planName = isTrial ? `₹${transaction.amount} Trial Gold` : 'Monthly Gold';

        const transactionId = transaction.gatewayTransactionId || transaction.paymentId || transaction.orderId;

        // 1. DEDUPLICATION CHECK: Ensure we don't add the same transaction twice
        const alreadyProcessed = await User.findOne({
            ...phoneQuery(normalizedPhone),
            'paymentHistory.orderId': transactionId
        });

        if (alreadyProcessed) {
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
            'subscription.autoRenew': true
        };

        if (transaction.orderId && (transaction.orderId.startsWith('sub_') || transaction.orderId.startsWith('S_'))) {
            updateFields['subscription.id'] = transaction.orderId;
        }

        const updatedUser = await User.findOneAndUpdate(
            phoneQuery(normalizedPhone),
            {
                $set: updateFields,
                $inc: { 'subscription.totalAmountPaid': transaction.amount },
                $push: {
                    paymentHistory: {
                        orderId: transactionId,
                        amount: transaction.amount,
                        status: 'SUCCESS',
                        method: method || 'UPI',
                        timestamp: now
                    }
                }
            },
            { new: true }
        );
        analyticsService.trackPremiumUpgrade(normalizedPhone);
        revenueService.trackPaymentEvent('payment_success', { userPhone: normalizedPhone, amount: transaction.amount, gateway: transaction.gateway || 'razorpay' });
        return updatedUser;
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
        const reviewConfig = await Config.findOne({ key: 'review_mode_config' });

        let isStandardMode = false;
        if (reviewConfig && reviewConfig.value) {
            const rc = reviewConfig.value;
            if (rc.isReviewMode === true) {
                isStandardMode = true;
            } else if (rc.isGradualEnabled === true) {
                const userCreated = new Date(user.createdAt).getTime();
                const monetizationStart = rc.monetizationStartDate ? new Date(rc.monetizationStartDate).getTime() : Date.now();
                if (userCreated < monetizationStart) {
                    isStandardMode = true;
                }
            }
        }

        if (isStandardMode) return { isPremium: false, status: 'review_mode', isStandardMode: true };

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
            offer: offerData,
            isStandardMode: false
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

    static async verifyPayment(phone, paymentData) {
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
                        if (subDetails && subDetails.current_end) {
                            currentPeriodEnd = subDetails.current_end; // This is the source of truth
                        }
                    } catch (err) { console.error("Error fetching sub details:", err); }
                }

                transaction = await PaymentTransaction.findOneAndUpdate(
                    { orderId, status: 'PENDING' },
                    {
                        status: 'SUCCESS',
                        gatewayTransactionId: verification.transactionId,
                        paymentMethod: paymentData.method || 'UPI',
                        current_period_end: currentPeriodEnd // Store the truth
                    },
                    { new: true }
                );

                if (!transaction && gateway === 'google_play') {
                    // (Google Play logic remains same...)
                    let amount = paymentData.amount || 199;
                    transaction = await PaymentTransaction.create({
                        orderId, userPhone: normalizedPhone, gateway: 'google_play',
                        amount, status: 'SUCCESS', gatewayTransactionId: verification.transactionId,
                        paymentMethod: 'Google Play'
                    });
                }

                if (!transaction) {
                    const alreadyDone = await PaymentTransaction.findOne({ orderId, status: 'SUCCESS' });
                    if (alreadyDone) return { success: true, user: await User.findOne(phoneQuery(normalizedPhone)) };
                    throw new Error("Invalid or duplicate transaction");
                }

                const updatedUser = await this._updateUserSubscription(normalizedPhone, transaction, transaction.paymentMethod);
                return { success: true, user: updatedUser };
            }
            return { success: false, message: "Verification failed" };
        } catch (e) { return { success: false, message: e.message }; }
    }

    static async processWebhook(gateway, payload, signature, rawBody) {
        try {
            const provider = await this.getProvider(gateway);
            const result = await provider.handleWebhook(payload, signature, rawBody);
            const phone = result.userPhone;

            if (!phone || phone === 'UNKNOWN') return { success: true };

            // ENSURE TRANSACTION OBJECT HAS LATEST DATA FROM WEBHOOK
            let transaction = await PaymentTransaction.findOne({ orderId: result.orderId });
            if (!transaction) {
                transaction = await PaymentTransaction.create({
                    orderId: result.paymentId || result.orderId,
                    userPhone: phone, gateway,
                    amount: result.amount || 0, status: 'SUCCESS',
                    gatewayTransactionId: result.paymentId,
                    current_period_end: result.current_period_end
                });
            } else {
                transaction.status = 'SUCCESS';
                if (result.paymentId) transaction.gatewayTransactionId = result.paymentId;
                if (result.current_period_end) transaction.current_period_end = result.current_period_end;
                await transaction.save();
            }

            // USER STATE MACHINE HANDLING
            switch (result.status) {
                case 'TRIAL_SUCCESS':
                    // User paid ₹1, start 24h trial
                    await this._updateUserSubscription(phone, result, 'Razorpay UPI');
                    break;

                case 'RENEWAL_SUCCESS':
                    // User paid ₹199, mark as active monthly member
                    await this._updateUserSubscription(phone, result, 'Razorpay Auto-Debit');
                    break;

                case 'CANCELLED':
                    // Just turn off auto-renew, keep premium until current expiry
                    await User.findOneAndUpdate(phoneQuery(phone), {
                        $set: { 'subscription.autoRenew': false, 'subscription.status': 'cancelled' }
                    });
                    break;

                case 'PAYMENT_FAILED':
                    // Notify system of failure, maybe give 2 days grace period
                    await User.findOneAndUpdate(phoneQuery(phone), {
                        $set: { 'subscription.status': 'payment_failed' }
                    });
                    break;

                case 'EXPIRED':
                    // Access Revoked
                    await this.revokeSubscription(phone, 'expired');
                    break;

                case 'SUCCESS':
                    // General fallback for single payments
                    await this._updateUserSubscription(phone, result, 'Razorpay');
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
