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

        // Activate Premium instantly
        const expiryDate = new Date();
        expiryDate.setDate(expiryDate.getDate() + 30); // Base month + 24h trial included implicitly

        const updatedUser = await User.findOneAndUpdate(
            { phone },
            {
                isPremium: true,
                premiumExpiry: expiryDate,
                premiumPlan: 'Monthly Gold',
                $push: {
                    paymentHistory: {
                        orderId: razorpay_subscription_id,
                        paymentId: razorpay_payment_id,
                        amount: 1, // The upfront ₹1
                        status: "Premium Activated",
                        timestamp: new Date()
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
        const secret = webhookSecret || keySecret; // Use specific secret or fallback to Key Secret
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

        if (event === 'subscription.activated' || event === 'payment.captured') {
            const subscriptionId = payload.subscription ? payload.subscription.entity.id : payload.payment.entity.subscription_id;
            const phone = payload.subscription ? payload.subscription.entity.notes.phone : payload.payment.entity.notes.phone;
            const paymentId = payload.payment ? payload.payment.entity.id : null;

            if (subscriptionId && phone) {
                // Activate Premium with Idempotency check
                const user = await User.findOne({ phone: phone });
                if (user && (!user.isPremium || !user.paymentHistory.some(p => p.orderId === subscriptionId))) {
                    const expiryDate = new Date();
                    expiryDate.setDate(expiryDate.getDate() + 30);

                    await User.findOneAndUpdate(
                        { phone: phone },
                        {
                            isPremium: true,
                            premiumPlan: 'Monthly Gold',
                            premiumExpiry: expiryDate,
                            $addToSet: { // Avoid duplicates in history
                                paymentHistory: {
                                    orderId: subscriptionId,
                                    paymentId: paymentId,
                                    amount: 1,
                                    status: "Activated via Webhook",
                                    timestamp: new Date()
                                }
                            }
                        }
                    );
                    console.log(`✅ Premium activated via Webhook for ${phone}`);
                }
            }
        }

        res.json({ status: 'ok' });
    } catch (err) {
        console.error("Webhook Error:", err);
        res.status(500).send('Error');
    }
};
