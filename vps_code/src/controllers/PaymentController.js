const Razorpay = require('razorpay');
const crypto = require('crypto');
const User = require('../models/User');
const Config = require('../models/Config');

const getRazorpayConfig = async () => {
    const config = await Config.findOne({ key: 'razorpay_keys' });
    const keys = config ? config.value : null;
    if (!keys?.keyId || !keys?.keySecret || !keys?.planId) {
        throw new Error("Razorpay Key ID, Secret, or Plan ID missing in Dashboard.");
    }
    return keys;
};

// 1. Create Subscription (with 1 Day Trial + ₹1 Upfront Verification)
exports.createOrder = async (req, res) => {
    try {
        console.log("Creating subscription for:", req.body.phone);
        const { keyId, keySecret, planId } = await getRazorpayConfig();
        const razorpay = new Razorpay({ key_id: keyId, key_secret: keySecret });

        // Billing starts after 24 hours
        const startAt = Math.floor(Date.now() / 1000) + (24 * 60 * 60);

        const subscriptionRequest = {
            plan_id: planId,
            total_count: 12, // 1 year of recurring monthly billing
            quantity: 1,
            customer_notify: 1,
            start_at: startAt,
            // Upfront ₹1 non-refundable trial/verification charge
            addons: [
                {
                    item: {
                        name: "One-time Trial Activation",
                        amount: 100, // 100 paise = ₹1
                        currency: "INR"
                    }
                }
            ],
            notes: {
                phone: req.body.phone, // Crucial for Webhook identification
                purpose: "Premium Gold Activation",
                trial: "24h"
            }
        };

        const subscription = await razorpay.subscriptions.create(subscriptionRequest);
        res.json({ success: true, subscription, keyId });
    } catch (error) {
        console.error("Subscription Error:", error.message);
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. Verify Subscription Payment (Immediate Activation)
exports.verifyPayment = async (req, res) => {
    try {
        const { razorpay_subscription_id, razorpay_payment_id, razorpay_signature, phone } = req.body;
        const { keySecret } = await getRazorpayConfig();

        const body = razorpay_payment_id + "|" + razorpay_subscription_id;
        const expectedSignature = crypto
            .createHmac("sha256", keySecret)
            .update(body.toString())
            .digest("hex");

        if (expectedSignature !== razorpay_signature) {
            return res.status(400).json({ success: false, message: "Invalid Signature" });
        }

        // Activate Premium instantly for the user
        const now = new Date();
        const trialExpiry = new Date(now.getTime() + (24 * 60 * 60 * 1000)); // 24 hours
        const premiumExpiry = new Date(now.getTime() + (31 * 24 * 60 * 60 * 1000)); // 1 Month

        const updatedUser = await User.findOneAndUpdate(
            { phone },
            {
                isPremium: true,
                premiumExpiry: premiumExpiry,
                premiumPlan: 'Monthly Gold',
                subscription: {
                    id: razorpay_subscription_id,
                    status: 'trial_active',
                    trialStartDate: now,
                    trialEndDate: trialExpiry,
                    startDate: now,
                    nextBillingDate: trialExpiry, // Billing starts after 24h
                    autoRenew: true,
                    lastPaymentDate: now,
                    totalAmountPaid: 1,
                    paymentMethod: 'UPI'
                },
                $push: {
                    paymentHistory: {
                        orderId: razorpay_subscription_id,
                        paymentId: razorpay_payment_id,
                        amount: 1,
                        status: "Success",
                        method: "UPI",
                        timestamp: now
                    }
                }
            },
            { new: true }
        );

        res.json({ success: true, user: updatedUser });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 3. Webhook Handler (Production Security)
exports.handleWebhook = async (req, res) => {
    try {
        const { keySecret, webhookSecret } = await getRazorpayConfig();
        const secret = webhookSecret || keySecret;
        const signature = req.headers['x-razorpay-signature'];

        const expectedSignature = crypto
            .createHmac('sha256', secret)
            .update(JSON.stringify(req.body))
            .digest('hex');

        if (signature !== expectedSignature) {
            return res.status(400).send('Invalid Signature');
        }

        const event = req.body.event;
        const payload = req.body.payload;

        console.log(`🔔 Razorpay Webhook Received: ${event}`);

        switch (event) {
            case 'subscription.charged':
                await handleSubscriptionCharged(payload);
                break;
            case 'subscription.cancelled':
                await handleSubscriptionCancelled(payload);
                break;
            case 'subscription.expired':
                await handleSubscriptionExpired(payload);
                break;
            case 'payment.failed':
                await handlePaymentFailed(payload);
                break;
        }

        if (event === 'subscription.charged' || event === 'payment.failed' || event === 'subscription.cancelled') {
            const sub = payload.subscription ? payload.subscription.entity : null;
            const phone = sub ? sub.notes.phone : (payload.payment ? payload.payment.entity.notes.phone : null);

            if (phone) {
                // Emit socket event for real-time premium update
                const io = req.app.get('socketio');
                if (io) {
                    io.emit(`premium_update_${phone}`, { event: event });
                }
            }
        }

        res.json({ status: 'ok' });
    } catch (err) {
        console.error("Webhook Error:", err);
        res.status(500).send('Error');
    }
};

async function handleSubscriptionCharged(payload) {
    const sub = payload.subscription.entity;
    const payment = payload.payment.entity;
    const phone = sub.notes.phone;

    const amount = payment.amount / 100;
    const nextBilling = sub.current_end ? new Date(sub.current_end * 1000) : null;

    await User.findOneAndUpdate(
        { phone: phone },
        {
            isPremium: true,
            premiumPlan: 'Monthly Gold',
            premiumExpiry: nextBilling ? new Date(nextBilling.getTime() + (24 * 60 * 60 * 1000)) : undefined,
            'subscription.status': 'active',
            'subscription.nextBillingDate': nextBilling,
            'subscription.lastPaymentDate': new Date(),
            'subscription.paymentMethod': payment.method,
            $inc: { 'subscription.totalAmountPaid': amount },
            $push: {
                paymentHistory: {
                    orderId: sub.id,
                    paymentId: payment.id,
                    amount: amount,
                    status: "Success",
                    method: payment.method,
                    timestamp: new Date()
                }
            }
        }
    );
}

async function handleSubscriptionCancelled(payload) {
    const sub = payload.subscription.entity;
    const phone = sub.notes.phone;

    await User.findOneAndUpdate(
        { phone: phone },
        {
            'subscription.status': 'cancelled',
            'subscription.autoRenew': false,
            'subscription.cancellationDate': new Date()
        }
    );
}

async function handleSubscriptionExpired(payload) {
    const sub = payload.subscription.entity;
    const phone = sub.notes.phone;

    await User.findOneAndUpdate(
        { phone: phone },
        {
            isPremium: false,
            'subscription.status': 'expired',
            'subscription.autoRenew': false
        }
    );
}

async function handlePaymentFailed(payload) {
    const payment = payload.payment.entity;
    const phone = payment.notes.phone;

    await User.findOneAndUpdate(
        { phone: phone },
        {
            'subscription.status': 'payment_failed',
            $push: {
                paymentHistory: {
                    orderId: payment.subscription_id,
                    paymentId: payment.id,
                    amount: payment.amount / 100,
                    status: "Failed",
                    method: payment.method,
                    timestamp: new Date()
                }
            }
        }
    );
}
