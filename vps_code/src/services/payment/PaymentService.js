const Config = require('../../models/Config');
const RazorpayProvider = require('./RazorpayProvider');
const PhonePeProvider = require('./PhonePeProvider');
const CashfreeProvider = require('./CashfreeProvider');
const PaymentTransaction = require('../../models/PaymentTransaction');
const User = require('../../models/User');
const analyticsService = require('../analyticsService');
const revenueService = require('../revenueService');

class PaymentService {
    static async getProvider() {
        const config = await Config.findOne({ key: 'payment_settings' });
        if (!config) throw new Error("Payment settings not configured");

        const settings = config.value;
        const activeGateway = settings.activeGateway;

        switch (activeGateway) {
            case 'razorpay':
                return new RazorpayProvider(settings.razorpay);
            case 'phonepe':
                return new PhonePeProvider(settings.phonepe);
            case 'cashfree':
                return new CashfreeProvider(settings.cashfree);
            default:
                throw new Error(`Unsupported gateway: ${activeGateway}`);
        }
    }

    static async createOrder(phone) {
        const provider = await this.getProvider();
        const user = await User.findOne({ phone });
        const hasUsedTrial = user?.subscription?.hasUsedTrial || false;

        // Logic for amount: ₹1 for trial, else ₹199
        const amount = hasUsedTrial ? 199 : 1;

        const orderData = await provider.createOrder({
            phone,
            amount,
            isSubscription: true // Defaulting to subscription behavior if supported
        });

        if (orderData.success) {
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
        const trialDays = (transaction.amount === 1) ? 1 : 0;

        // Fetch user to calculate new expiry correctly
        const user = await User.findOne({ phone });
        if (!user) return null;

        // Calculate new expiry: if already premium and not expired, extend from existing expiry
        let baseDate = (user.premiumExpiry && user.premiumExpiry > now) ? user.premiumExpiry : now;
        const newExpiry = new Date(baseDate.getTime() + (30 * 24 * 60 * 60 * 1000) + (trialDays * 24 * 60 * 60 * 1000));

        const updateFields = {
            isPremium: true,
            premiumExpiry: newExpiry,
            premiumPlan: transaction.amount === 1 ? '₹1 Trial Gold' : 'Monthly Gold',
            'subscription.id': transaction.orderId,
            'subscription.status': trialDays > 0 ? 'trial_active' : 'active',
            'subscription.hasUsedTrial': true,
            'subscription.startDate': now, // Start of current billing cycle
            'subscription.nextBillingDate': newExpiry,
            'subscription.lastPaymentDate': now,
            'subscription.paymentMethod': method || 'UPI',
        };

        if (trialDays > 0) {
            updateFields['subscription.trialStartDate'] = now;
            updateFields['subscription.trialEndDate'] = new Date(now.getTime() + (1 * 24 * 60 * 60 * 1000));
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
        const provider = await this.getProvider();
        const verification = await provider.verifyPayment(paymentData);

        if (verification.success) {
            const transaction = await PaymentTransaction.findOneAndUpdate(
                {
                    orderId: paymentData.orderId || paymentData.razorpay_subscription_id || paymentData.merchantTransactionId,
                    status: { $ne: 'SUCCESS' }
                },
                {
                    status: 'SUCCESS',
                    gatewayTransactionId: verification.transactionId,
                    paymentMethod: paymentData.method || 'UPI'
                },
                { new: true }
            );

            if (!transaction) {
                // Transaction was already marked success by webhook
                const user = await User.findOne({ phone });
                return { success: true, user };
            }

            const updatedUser = await this._updateUserSubscription(phone, transaction, paymentData.method);
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
        }

        return { success: true };
    }
}

module.exports = PaymentService;
