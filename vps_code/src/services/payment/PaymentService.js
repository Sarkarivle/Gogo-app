const Config = require('../../models/Config');
const RazorpayProvider = require('./RazorpayProvider');
const PhonePeProvider = require('./PhonePeProvider');
const CashfreeProvider = require('./CashfreeProvider');
const GooglePlayProvider = require('./GooglePlayProvider');
const PaymentTransaction = require('../../models/PaymentTransaction');
const User = require('../../models/User');
const analyticsService = require('../analyticsService');
const revenueService = require('../revenueService');

class PaymentService {
    static async getProvider(gatewayName) {
        const config = await Config.findOne({ key: 'payment_settings' });
        if (!config) throw new Error("Payment settings not configured");

        const settings = config.value;
        const gpConfig = await Config.findOne({ key: 'google_play_settings' });
        const gpSettings = gpConfig ? gpConfig.value : (settings.google_play || {});

        const gateway = gatewayName || settings.activeGateway;

        switch (gateway.toLowerCase()) {
            case 'razorpay':
                return new RazorpayProvider(settings.razorpay);
            case 'phonepe':
                return new PhonePeProvider(settings.phonepe);
            case 'cashfree':
                return new CashfreeProvider(settings.cashfree);
            case 'google_play':
                return new GooglePlayProvider(gpSettings);
            default:
                throw new Error(`Unsupported gateway: ${gateway}`);
        }
    }

    static async createOrder(phone, preferredGateway) {
        const provider = await this.getProvider(preferredGateway);
        const user = await User.findOne({ phone });
        const hasUsedTrial = user?.subscription?.hasUsedTrial || false;

        // Logic for amount: ₹1 for trial, else ₹199
        const amount = hasUsedTrial ? 199 : 1;

        const orderData = await provider.createOrder({
            phone,
            amount,
            isSubscription: true
        });

        if (orderData.success && orderData.orderId) {
            await PaymentTransaction.create({
                orderId: orderData.orderId,
                userPhone: phone,
                gateway: orderData.gateway,
                amount: amount,
                status: 'PENDING',
                metadata: orderData
            });
        }

        return orderData;
    }

    static async _updateUserSubscription(phone, transaction, method) {
        const now = new Date();
        const isTrial = (transaction.amount === 1);
        const durationDays = isTrial ? 1 : 30; // ₹1 = 24h trial, ₹199 = 30 days

        // Fetch user to calculate new expiry correctly
        const user = await User.findOne({ phone });
        if (!user) return null;

        // Calculate new expiry: if already premium and not expired, extend from existing expiry
        let baseDate = (user.premiumExpiry && user.premiumExpiry > now) ? user.premiumExpiry : now;
        const newExpiry = new Date(baseDate.getTime() + (durationDays * 24 * 60 * 60 * 1000));

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

        // Ensure we don't overwrite subscription ID with individual payment IDs
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
            { phone },
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

        analyticsService.trackPremiumUpgrade(phone);
        revenueService.trackPaymentEvent('payment_success', {
            userPhone: phone,
            amount: transaction.amount,
            gateway: transaction.gateway || 'razorpay'
        });

        return updatedUser;
    }

    static async verifyPayment(phone, paymentData) {
        const gateway = paymentData.gateway || 'razorpay';
        const provider = await this.getProvider(gateway);

        // SECURE: Verify signature/receipt with gateway
        const verification = await provider.verifyPayment(paymentData);

        if (verification.success) {
            // For Google Play, we might not have a PENDING transaction yet
            let transaction;
            const orderId = paymentData.orderId || paymentData.razorpay_subscription_id || paymentData.merchantTransactionId || verification.transactionId;

            transaction = await PaymentTransaction.findOneAndUpdate(
                {
                    orderId: orderId,
                    status: 'PENDING'
                },
                {
                    status: 'SUCCESS',
                    gatewayTransactionId: verification.transactionId,
                    paymentMethod: paymentData.method || (gateway === 'google_play' ? 'Google Play' : 'UPI')
                },
                { new: true }
            );

            if (!transaction && gateway === 'google_play') {
                // Auto-create transaction for Google Play if not exists
                transaction = await PaymentTransaction.create({
                    orderId: orderId,
                    userPhone: phone,
                    gateway: 'google_play',
                    amount: paymentData.amount || 199,
                    status: 'SUCCESS',
                    gatewayTransactionId: verification.transactionId,
                    paymentMethod: 'Google Play'
                });
            }

            if (!transaction) {
                const alreadyDone = await PaymentTransaction.findOne({
                    orderId: orderId,
                    status: 'SUCCESS'
                });
                if (alreadyDone) {
                    const user = await User.findOne({ phone });
                    return { success: true, user };
                }
                throw new Error("Invalid or duplicate transaction");
            }

            const updatedUser = await this._updateUserSubscription(phone, transaction, transaction.paymentMethod);
            return { success: true, user: updatedUser };
        }

        return { success: false, message: "Verification failed" };
    }

    static async processWebhook(gateway, payload, signature, rawBody) {
        const config = await Config.findOne({ key: 'payment_settings' });
        const settings = config.value;

        let provider;
        if (gateway === 'razorpay') provider = new RazorpayProvider(settings.razorpay);
        else if (gateway === 'phonepe') provider = new PhonePeProvider(settings.phonepe);
        else if (gateway === 'cashfree') provider = new CashfreeProvider(settings.cashfree);

        const result = await provider.handleWebhook(payload, signature, rawBody);

        if (result.status === 'SUCCESS') {
            // Avoid duplicate processing if paymentId exists
            if (result.paymentId) {
                const alreadyProcessed = await User.findOne({ 'paymentHistory.orderId': result.paymentId });
                if (alreadyProcessed) return { success: true, message: "Already processed" };
            }

            let transaction = await PaymentTransaction.findOne({ orderId: result.orderId });

            if (!transaction) {
                // Create transaction if it doesn't exist (e.g. background recurring payment)
                transaction = await PaymentTransaction.create({
                    orderId: result.paymentId || result.orderId,
                    userPhone: result.userPhone || 'UNKNOWN',
                    gateway: gateway,
                    amount: result.amount || 0,
                    status: 'SUCCESS',
                    gatewayTransactionId: result.paymentId,
                    metadata: result.raw
                });
            } else if (transaction.status !== 'SUCCESS') {
                transaction.status = 'SUCCESS';
                transaction.gatewayTransactionId = result.paymentId;
                if (result.amount) transaction.amount = result.amount;
                await transaction.save();
            } else if (result.event === 'subscription.charged') {
                // This is a recurring charge, create a new transaction record
                transaction = await PaymentTransaction.create({
                    orderId: result.paymentId, // Use paymentId as orderId for uniqueness
                    userPhone: transaction.userPhone,
                    gateway: gateway,
                    amount: result.amount,
                    status: 'SUCCESS',
                    gatewayTransactionId: result.paymentId,
                    gatewaySubscriptionId: result.orderId, // This is the sub_... ID
                    metadata: result.raw
                });
            } else {
                return { success: true, message: "Already processed" };
            }

            if (transaction.userPhone && transaction.userPhone !== 'UNKNOWN') {
                await this._updateUserSubscription(transaction.userPhone, transaction, result.method);
            } else if (result.userPhone) {
                await this._updateUserSubscription(result.userPhone, transaction, result.method);
            }
        } else if (result.status === 'CANCELLED' || result.status === 'FAILED') {
            // Update user subscription status on failure/cancellation
            await User.findOneAndUpdate(
                { 'subscription.id': result.orderId },
                {
                    $set: {
                        'subscription.status': result.status.toLowerCase(),
                        'subscription.autoRenew': false,
                    }
                }
            );
        }

        return { success: true };
    }
}

module.exports = PaymentService;
