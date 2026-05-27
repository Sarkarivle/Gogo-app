const Razorpay = require('razorpay');
const PaymentProvider = require('./PaymentProvider');
const crypto = require('crypto');

class RazorpayProvider extends PaymentProvider {
    constructor(config) {
        super(config);
        if (!config || !config.keyId || !config.keySecret) {
            throw new Error("Razorpay configuration (keyId or keySecret) is missing.");
        }
        this.client = new Razorpay({
            key_id: config.keyId,
            key_secret: config.keySecret
        });
    }

    async createOrder({ phone, amount, isSubscription = true }) {
        if (isSubscription) {
            const subscription = await this.client.subscriptions.create({
                plan_id: this.config.planId,
                total_count: 12,
                quantity: 1,
                customer_notify: 1,
                notes: { phone }
            });
            return {
                success: true,
                orderId: subscription.id,
                subscription: subscription,
                keyId: this.config.keyId,
                gateway: 'razorpay'
            };
        } else {
            const order = await this.client.orders.create({
                amount: amount * 100, // paise
                currency: "INR",
                receipt: "rcpt_" + Date.now(),
                notes: { phone }
            });
            return {
                success: true,
                orderId: order.id,
                order: order,
                keyId: this.config.keyId,
                gateway: 'razorpay'
            };
        }
    }

    async verifyPayment({ razorpay_payment_id, razorpay_subscription_id, razorpay_order_id, razorpay_signature }) {
        // For subscriptions: payment_id | subscription_id
        // For orders: order_id | payment_id
        let body;
        if (razorpay_subscription_id) {
            body = razorpay_payment_id + "|" + razorpay_subscription_id;
        } else {
            body = (razorpay_order_id || "") + "|" + razorpay_payment_id;
        }

        const expectedSignature = crypto
            .createHmac("sha256", this.config.keySecret)
            .update(body.toString())
            .digest("hex");

        if (expectedSignature === razorpay_signature) {
            return { success: true, transactionId: razorpay_payment_id };
        }
        throw new Error("Invalid Razorpay signature");
    }

    async handleWebhook(payload, signature) {
        const expectedSignature = crypto
            .createHmac("sha256", this.config.webhookSecret)
            .update(JSON.stringify(payload))
            .digest("hex");

        if (expectedSignature !== signature) {
            throw new Error("Invalid webhook signature");
        }

        const payment = payload.payload.payment ? payload.payload.payment.entity : null;
        const subscription = payload.payload.subscription ? payload.payload.subscription.entity : null;

        // Normalized Status mapping
        let status = 'FAILED';
        if (payload.event === 'subscription.charged' || payload.event === 'payment.captured') {
            status = 'SUCCESS';
        } else if (payload.event === 'subscription.cancelled' || payload.event === 'subscription.expired') {
            status = 'CANCELLED';
        } else if (payload.event === 'subscription.halted' || payload.event === 'subscription.pending') {
            status = 'PENDING_FAIL';
        }

        // Return normalized event
        return {
            event: payload.event,
            orderId: subscription ? subscription.id : (payment ? payment.order_id : null),
            paymentId: payment ? payment.id : null,
            amount: payment ? (payment.amount / 100) : 0, // Convert paise to INR
            userPhone: (payment && payment.notes) ? payment.notes.phone : (subscription && subscription.notes ? subscription.notes.phone : null),
            status: status,
            raw: payload
        };
    }
}

module.exports = RazorpayProvider;
