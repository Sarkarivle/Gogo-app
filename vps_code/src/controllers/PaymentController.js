const PaymentService = require('../services/payment/PaymentService');
const Config = require('../models/Config');
const { normalize } = require('../utils/phoneUtils');

const getPublicSettings = async (req, res) => {
    try {
        const [payConfig, gpConfig, reviewConfig] = await Promise.all([
            Config.findOne({ key: 'payment_settings' }),
            Config.findOne({ key: 'google_play_settings' }),
            Config.findOne({ key: 'review_mode_config' })
        ]);

        const settings = payConfig?.value || {};
        const gpSettings = gpConfig?.value || {};

        // Robust check for isReviewMode within the value object
        let isStandardMode = false;
        let isOneMessageTrialEnabled = false;
        let isScreenshotDisabled = true;
        if (reviewConfig && reviewConfig.value) {
            isStandardMode = reviewConfig.value.isReviewMode === true;
            isOneMessageTrialEnabled = reviewConfig.value.isOneMessageTrialEnabled === true;
            isScreenshotDisabled = reviewConfig.value.isScreenshotDisabled !== false;
        }

        console.log(`🛡️  Compliance Status: StandardMode=${isStandardMode}, 1MsgTrial=${isOneMessageTrialEnabled}, ScreenshotDisabled=${isScreenshotDisabled}`);

        res.json({
            success: true,
            isStandardMode: isStandardMode,
            isOneMessageTrialEnabled: isOneMessageTrialEnabled,
            isScreenshotDisabled: isScreenshotDisabled,
            activeGateway: settings.activeGateway || 'razorpay',
            config: {
                isUpiEnabled: settings.isUpiEnabled !== false,
                isGooglePlayEnabled: gpSettings.isEnabled === true || settings.isGooglePlayEnabled === true,
                trialPrice: settings.trialPrice || 1,
                monthlyPrice: settings.monthlyPrice || 199
            }
        });
    } catch (e) {
        res.json({ success: true, isStandardMode: false, activeGateway: 'razorpay', config: { isUpiEnabled: true, isGooglePlayEnabled: false } });
    }
};

const createOrder = async (req, res) => {
    try {
        let { phone, preferredGateway } = req.body;
        // Identity check: Always prefer token phone for users
        if (req.user && !req.user.role) phone = req.user.phone;

        if (!phone) return res.status(400).json({ success: false, message: "Phone is required" });
        const normalizedPhone = normalize(phone);

        const orderData = await PaymentService.createOrder(normalizedPhone, preferredGateway);
        res.json(orderData);
    } catch (error) {
        console.error("Create Order Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

const verifyPayment = async (req, res) => {
    try {
        let { phone } = req.body;
        if (req.user && !req.user.role) phone = req.user.phone;

        if (!phone) return res.status(400).json({ success: false, message: "Phone is required" });
        const normalizedPhone = normalize(phone);

        const result = await PaymentService.verifyPayment(normalizedPhone, req.body);
        res.json(result);
    } catch (error) {
        console.error("Verify Payment Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

const syncUserStatus = async (req, res) => {
    try {
        let phone = req.user?.phone;
        if (!phone) return res.status(401).json({ success: false, message: "Unauthorized" });

        const status = await PaymentService.syncUserStatus(phone);
        res.json({ success: true, ...status });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

const cancelSubscription = async (req, res) => {
    try {
        const phone = req.user?.phone;
        if (!phone) return res.status(401).json({ success: false, message: "Unauthorized" });

        const result = await PaymentService.cancelSubscription(phone);

        // BROADCAST REFRESH (Targeted)
        const io = req.app.get('socketio');
        if (io) io.to(`user_${normalize(phone)}`).emit('premium_status_refresh', { phone: phone, message: "Subscription Cancelled ⚠️", type: "warning" });

        res.json(result);
    } catch (error) {
        console.error("Cancellation Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

const notifyStatusChange = async (req, res) => {
    try {
        const io = req.app.get('socketio');
        if (io) {
            io.emit('premium_status_refresh', { timestamp: new Date() });
            console.log("📢 Broadcast: Premium Status Refresh triggered for all users.");
        }
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

const handleRazorpayWebhook = async (req, res) => {
    try {
        const signature = req.headers['x-razorpay-signature'];
        await PaymentService.processWebhook('razorpay', req.body, signature);

        // REAL-TIME NOTIFICATION TO APP
        const io = req.app.get('socketio');
        if (io) {
            const payload = req.body;
            const phone = (payload.payload?.payment?.entity?.notes?.phone) ||
                          (payload.payload?.subscription?.entity?.notes?.phone);

            if (phone) {
                let message = "Account status updated";
                let type = "info";

                switch(payload.event) {
                    case 'subscription.authenticated':
                        message = "Trial Activated! Premium Features Unlocked 🚀";
                        type = "success";
                        break;
                    case 'subscription.charged':
                        message = "Payment Successful! Membership Renewed ✅";
                        type = "success";
                        break;
                    case 'payment.failed':
                    case 'subscription.halted':
                        message = "Payment Failed! Please check your balance ❌";
                        type = "error";
                        break;
                    case 'subscription.cancelled':
                        message = "Subscription Cancelled. Access remains until expiry ⚠️";
                        type = "warning";
                        break;
                }

                io.to(`user_${normalize(phone)}`).emit('premium_status_refresh', {
                    phone: phone,
                    message: message,
                    type: type
                });
                console.log(`📢 Webhook Broadcast: ${message} sent to ${phone}`);
            }
        }

        res.json({ status: 'ok' });
    } catch (err) {
        console.error("Razorpay Webhook Error:", err);
        res.status(400).send('Webhook Error');
    }
};

const handlePhonePeWebhook = async (req, res) => {
    try {
        const signature = req.headers['x-verify'];
        await PaymentService.processWebhook('phonepe', req.body, signature);
        res.json({ status: 'ok' });
    } catch (err) {
        console.error("PhonePe Webhook Error:", err);
        res.status(400).send('Webhook Error');
    }
};

const handleCashfreeWebhook = async (req, res) => {
    try {
        const signature = req.headers['x-webhook-signature'];
        const timestamp = req.headers['x-webhook-timestamp'];
        await PaymentService.processWebhook('cashfree', { timestamp, rawBody: JSON.stringify(req.body) }, signature);
        res.json({ status: 'ok' });
    } catch (err) {
        console.error("Cashfree Webhook Error:", err);
        res.status(400).send('Webhook Error');
    }
};

module.exports = {
    getPublicSettings,
    createOrder,
    verifyPayment,
    syncUserStatus,
    cancelSubscription,
    notifyStatusChange,
    handleRazorpayWebhook,
    handlePhonePeWebhook,
    handleCashfreeWebhook
};
