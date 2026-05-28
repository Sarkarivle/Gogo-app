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
        if (reviewConfig && reviewConfig.value) {
            isStandardMode = reviewConfig.value.isReviewMode === true;
        }

        console.log(`🛡️  Compliance Status: StandardMode=${isStandardMode}`);

        res.json({
            success: true,
            isStandardMode: isStandardMode,
            activeGateway: settings.activeGateway || 'razorpay',
            config: {
                isUpiEnabled: settings.isUpiEnabled !== false,
                isGooglePlayEnabled: gpSettings.isEnabled === true || settings.isGooglePlayEnabled === true
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
        // Identity check: Always prefer token phone for users
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

const handleRazorpayWebhook = async (req, res) => {
    try {
        const signature = req.headers['x-razorpay-signature'];
        await PaymentService.processWebhook('razorpay', req.body, signature);
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
    handleRazorpayWebhook,
    handlePhonePeWebhook,
    handleCashfreeWebhook
};
