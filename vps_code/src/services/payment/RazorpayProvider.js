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

    async createOrder({ phone, amount, isSubscription = true, isTrial = false, overridePlanId = null }) {
        if (isSubscription) {
            // Use overridePlanId for Win-back offers, otherwise fallback to default
            const targetPlanId = overridePlanId || this.config.planId;

            const subscriptionData = {
                plan_id: targetPlanId,
                total_count: 12,
                quantity: 1,
                customer_notify: 1,
                notes: { phone }
            };

            // 2. If it's a Trial user, set 24h delay and add ₹1 Add-on
            if (isTrial) {
                // Billing starts in 24 hours
                subscriptionData.start_at = Math.floor(Date.now() / 1000) + (24 * 60 * 60);

                // Add Trial Fee (e.g. ₹1)
                subscriptionData.addons = [
                    {
                        item: {
                            name: "Trial Period Access",
                            amount: amount * 100, // paise
                            currency: "INR"
                        }
                    }
                ];
            }

            const subscription = await this.client.subscriptions.create(subscriptionData);

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

        // MAP RAZORPAY EVENTS TO OUR STATE MACHINE
        let status = 'PENDING_FAIL';
        let eventType = payload.event;

        switch (payload.event) {
            case 'subscription.authenticated':
                status = 'TRIAL_SUCCESS'; // ₹1 Setup fee success
                break;
            case 'subscription.charged':
                status = 'RENEWAL_SUCCESS'; // ₹199 Monthly success
                break;
            case 'subscription.cancelled':
                status = 'CANCELLED';
                break;
            case 'subscription.expired':
                status = 'EXPIRED';
                break;
            case 'subscription.halted':
            case 'payment.failed':
                status = 'PAYMENT_FAILED';
                break;
            case 'payment.captured':
                status = 'SUCCESS';
                break;
        }

        return {
            event: eventType,
            orderId: subscription ? subscription.id : (payment ? payment.order_id : null),
            paymentId: payment ? payment.id : null,
            // Fetch actual amount from payment object if available, otherwise fallback to 0
            amount: payment ? (payment.amount / 100) : 0,
            userPhone: (payment && payment.notes) ? payment.notes.phone : (subscription && subscription.notes ? subscription.notes.phone : null),
            status: status,
            current_period_end: subscription ? subscription.current_end : null,
            next_billing_at: subscription ? subscription.next_billing_at : null,
            start_at: subscription ? subscription.start_at : null,
            raw: payload
        };
    }
}

module.exports = RazorpayProvider;
