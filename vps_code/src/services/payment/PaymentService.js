const Config = require('../../models/Config');
const RazorpayProvider = require('./RazorpayProvider');
const PhonePeProvider = require('./PhonePeProvider');
const CashfreeProvider = require('./CashfreeProvider');
const PaymentTransaction = require('../../models/PaymentTransaction');
const User = require('../../models/User');

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

            // Activate Premium
            const now = new Date();
            const trialDays = (transaction.amount === 1) ? 1 : 0; // ₹1 is 1-day trial
            const premiumExpiry = new Date(now.getTime() + ((30 + trialDays) * 24 * 60 * 60 * 1000));

            const subUpdate = {
                id: transaction.orderId,
                status: trialDays > 0 ? 'trial_active' : 'active',
                hasUsedTrial: true,
                startDate: now,
                nextBillingDate: premiumExpiry,
                totalAmountPaid: transaction.amount,
                lastPaymentDate: now,
                paymentMethod: paymentData.method || 'UPI'
            };

            if (trialDays > 0) {
                subUpdate.trialStartDate = now;
                subUpdate.trialEndDate = new Date(now.getTime() + (1 * 24 * 60 * 60 * 1000));
            }

            const updatedUser = await User.findOneAndUpdate(
                { phone },
                {
                    isPremium: true,
                    premiumExpiry: premiumExpiry,
                    premiumPlan: trialDays > 0 ? '₹1 Trial Gold' : 'Monthly Gold',
                    subscription: subUpdate,
                    $push: {
                        paymentHistory: {
                            orderId: transaction.orderId,
                            amount: transaction.amount,
                            status: 'SUCCESS',
                            method: paymentData.method || 'UPI',
                            timestamp: now
                        }
                    }
                },
                { new: true }
            );

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

        const transaction = await PaymentTransaction.findOneAndUpdate(
            { orderId: result.orderId, status: { $ne: 'SUCCESS' } },
            {
                status: result.status,
                $push: { webhookLogs: { timestamp: new Date(), payload: result.raw } }
            },
            { new: true }
        );

        if (!transaction) {
            // Already processed or not found
            const existing = await PaymentTransaction.findOne({ orderId: result.orderId });
            return { success: !!existing, message: existing ? "Already processed" : "Transaction not found" };
        }

        if (result.status === 'SUCCESS') {
            const now = new Date();
            const trialDays = (transaction.amount === 1) ? 1 : 0;
            const premiumExpiry = new Date(now.getTime() + ((30 + trialDays) * 24 * 60 * 60 * 1000));

            const subUpdate = {
                id: transaction.orderId,
                status: trialDays > 0 ? 'trial_active' : 'active',
                hasUsedTrial: true,
                startDate: now,
                nextBillingDate: premiumExpiry,
                totalAmountPaid: transaction.amount,
                lastPaymentDate: now,
                paymentMethod: transaction.paymentMethod || 'UPI'
            };

            if (trialDays > 0) {
                subUpdate.trialStartDate = now;
                subUpdate.trialEndDate = new Date(now.getTime() + (1 * 24 * 60 * 60 * 1000));
            }

            await User.findOneAndUpdate(
                { phone: transaction.userPhone },
                {
                    isPremium: true,
                    premiumExpiry: premiumExpiry,
                    premiumPlan: trialDays > 0 ? '₹1 Trial Gold' : 'Monthly Gold',
                    subscription: subUpdate,
                    $push: {
                        paymentHistory: {
                            orderId: transaction.orderId,
                            amount: transaction.amount,
                            status: 'SUCCESS',
                            method: transaction.paymentMethod || 'UPI',
                            timestamp: now
                        }
                    }
                }
            );
        }

        return { success: true };
    }
}

module.exports = PaymentService;
