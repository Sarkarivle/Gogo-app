const Config = require('../../models/Config');
const RazorpayProvider = require('./RazorpayProvider');
const PhonePeProvider = require('./PhonePeProvider');
const CashfreeProvider = require('./CashfreeProvider');
const GooglePlayProvider = require('./GooglePlayProvider');
const PaymentTransaction = require('../../models/PaymentTransaction');
const User = require('../../models/User');
const analyticsService = require('../analyticsService');
const revenueService = require('../revenueService');
const { normalize } = require('../../utils/phoneUtils');

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
            const user = await User.findOne({ phone: normalizedPhone });
            const hasUsedTrial = user?.subscription?.hasUsedTrial || false;
            const amount = hasUsedTrial ? 199 : 1;

            const orderData = await provider.createOrder({
                phone: normalizedPhone,
                amount,
                isSubscription: true
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
        const isTrial = (transaction.amount === 1);
        const durationHours = isTrial ? 23 : (30 * 24);
        const user = await User.findOne({ phone: normalizedPhone });
        if (!user) return null;
        let baseDate = (user.premiumExpiry && user.premiumExpiry > now) ? user.premiumExpiry : now;
        const newExpiry = new Date(baseDate.getTime() + (durationHours * 60 * 60 * 1000));
        const updateFields = {
            isPremium: true,
            premiumExpiry: newExpiry,
            premiumPlan: isTrial ? '₹1 Trial Gold' : 'Monthly Gold',
            'subscription.status': isTrial ? 'trial_active' : 'active',
            'subscription.hasUsedTrial': true,
            'subscription.startDate': now,
            'subscription.nextBillingDate': newExpiry,
            'subscription.lastPaymentDate': now,
            'subscription.paymentMethod': method || 'UPI',
            'subscription.autoRenew': true
        };
        if (transaction.orderId && transaction.orderId.startsWith('sub_')) {
            updateFields['subscription.id'] = transaction.orderId;
        } else if (transaction.gatewaySubscriptionId) {
            updateFields['subscription.id'] = transaction.gatewaySubscriptionId;
        }
        if (isTrial) {
            updateFields['subscription.trialStartDate'] = now;
            updateFields['subscription.trialEndDate'] = newExpiry;
        }
        const updatedUser = await User.findOneAndUpdate(
            { phone: normalizedPhone },
            {
                $set: updateFields,
                $inc: { 'subscription.totalAmountPaid': transaction.amount },
                $push: {
                    paymentHistory: {
                        orderId: transaction.gatewayTransactionId || transaction.orderId,
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

    static async verifyPayment(phone, paymentData) {
        try {
            const normalizedPhone = normalize(phone);
            const gateway = paymentData.gateway || 'razorpay';
            const provider = await this.getProvider(gateway);
            const verification = await provider.verifyPayment(paymentData);
            if (verification.success) {
                let transaction;
                const orderId = paymentData.orderId || paymentData.razorpay_subscription_id || paymentData.merchantTransactionId || verification.transactionId;
                transaction = await PaymentTransaction.findOneAndUpdate({ orderId, status: 'PENDING' }, { status: 'SUCCESS', gatewayTransactionId: verification.transactionId, paymentMethod: paymentData.method || (gateway === 'google_play' ? 'Google Play' : 'UPI') }, { new: true });
                if (!transaction && gateway === 'google_play') {
                    // FIX: Determine amount based on productId for Google Play
                    let amount = paymentData.amount || 199;
                    if (paymentData.productId && (paymentData.productId.includes('trial') || paymentData.productId.includes('rs1'))) {
                        amount = 1;
                    }
                    transaction = await PaymentTransaction.create({
                        orderId,
                        userPhone: normalizedPhone,
                        gateway: 'google_play',
                        amount: amount,
                        status: 'SUCCESS',
                        gatewayTransactionId: verification.transactionId,
                        paymentMethod: 'Google Play'
                    });
                }
                if (!transaction) {
                    const alreadyDone = await PaymentTransaction.findOne({ orderId, status: 'SUCCESS' });
                    if (alreadyDone) return { success: true, user: await User.findOne({ phone: normalizedPhone }) };
                    throw new Error("Invalid or duplicate transaction");
                }
                const updatedUser = await this._updateUserSubscription(normalizedPhone, transaction, transaction.paymentMethod);
                return { success: true, user: updatedUser };
            }
            return { success: false, message: "Verification failed" };
        } catch (e) {
            return { success: false, message: e.message };
        }
    }

    static async processWebhook(gateway, payload, signature, rawBody) {
        try {
            const provider = await this.getProvider(gateway);
            const result = await provider.handleWebhook(payload, signature, rawBody);

            if (result.status === 'SUCCESS') {
                if (result.paymentId) {
                    const alreadyProcessed = await User.findOne({ 'paymentHistory.orderId': result.paymentId });
                    if (alreadyProcessed) return { success: true };
                }
                let transaction = await PaymentTransaction.findOne({ orderId: result.orderId });
                if (!transaction) {
                    transaction = await PaymentTransaction.create({ orderId: result.paymentId || result.orderId, userPhone: result.userPhone || 'UNKNOWN', gateway, amount: result.amount || 0, status: 'SUCCESS', gatewayTransactionId: result.paymentId, metadata: result.raw });
                } else if (transaction.status !== 'SUCCESS') {
                    transaction.status = 'SUCCESS';
                    transaction.gatewayTransactionId = result.paymentId;
                    if (result.amount) transaction.amount = result.amount;
                    await transaction.save();
                }
                if (transaction.userPhone && transaction.userPhone !== 'UNKNOWN') await this._updateUserSubscription(transaction.userPhone, transaction, result.method);
            }
            return { success: true };
        } catch (e) { return { success: false }; }
    }
}

module.exports = PaymentService;
