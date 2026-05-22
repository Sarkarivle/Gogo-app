const PaymentService = require('../services/payment/PaymentService');
const Config = require('../models/Config');

const getPublicSettings = async (req, res) => {
    try {
        const config = await Config.findOne({ key: 'payment_settings' });
        const activeGateway = config?.value?.activeGateway || 'razorpay';
        res.json({ success: true, activeGateway });
    } catch (e) {
        res.json({ success: true, activeGateway: 'razorpay' });
    }
};

const createOrder = async (req, res) => {
    try {
        const { phone } = req.body;
        if (!phone) return res.status(400).json({ success: false, message: "Phone is required" });

        const orderData = await PaymentService.createOrder(phone);
        res.json(orderData);
    } catch (error) {
        console.error("Create Order Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

const verifyPayment = async (req, res) => {
    try {
        const { phone } = req.body;
        if (!phone) return res.status(400).json({ success: false, message: "Phone is required" });

        const result = await PaymentService.verifyPayment(phone, req.body);
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
