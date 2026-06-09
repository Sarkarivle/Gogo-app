const PaymentService = require('../services/payment/PaymentService');
const Config = require('../models/Config');
const User = require('../models/User'); // Import at top
const { normalize } = require('../utils/phoneUtils');
const jwt = require('jsonwebtoken');
const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

/**
 * Shared Logic to determine if user should be in Standard Mode
 * (Duplicate from UserController for reliability)
 */
function determineStandardMode(user, config) {
    if (!config) return false;
    if (config.isReviewMode === true) return true;
    if (config.isGradualEnabled === true && user) {
        if (!config.monetizationStartDate) return false;
        const userCreated = new Date(user.createdAt).getTime();
        const monetizationStart = new Date(config.monetizationStartDate).getTime();
        return userCreated < monetizationStart;
    }
    return false;
}

exports.getPublicSettings = async (req, res) => {
    try {
        const [payConfig, gpConfig, reviewConfig] = await Promise.all([
            Config.findOne({ key: 'payment_settings' }),
            Config.findOne({ key: 'google_play_settings' }),
            Config.findOne({ key: 'review_mode_config' })
        ]);

        const settings = payConfig?.value || {};
        const gpSettings = gpConfig?.value || {};

        // HYBRID FIX: Manually check for token to identify user
        let user = null;
        const authHeader = req.headers.authorization;
        if (authHeader && authHeader.startsWith('Bearer ')) {
            try {
                const token = authHeader.split(' ')[1];
                const decoded = jwt.verify(token, JWT_SECRET);
                if (decoded && decoded.phone) {
                    user = await User.findOne({ phone: normalize(decoded.phone) });
                }
            } catch (err) {
                // Ignore invalid tokens
            }
        }

        const config = reviewConfig?.value || {};
        const isStandardMode = determineStandardMode(user, config);

        // Trial logic: Trial is only allowed if global trial is enabled
        // AND user is either a Reviewer (Global ON) OR a New User (Standard OFF)
        // OLD USERS (Standard ON) should NOT be restricted by 1-msg trial if Gradual is ON
        let isOneMessageTrialEnabled = config.isOneMessageTrialEnabled === true;

        if (isStandardMode && config.isReviewMode === false && config.isGradualEnabled === true) {
            // This is an OLD USER in Hybrid mode -> Force trial OFF (Unlimited Access)
            isOneMessageTrialEnabled = false;
        }

        console.log(`🛡️ Compliance: User=${user?.phone || 'Guest'}, Mode=${isStandardMode ? 'STANDARD' : 'LIVE'}, Trial=${isOneMessageTrialEnabled}`);

        res.json({
            success: true,
            isStandardMode: isStandardMode,
            isOneMessageTrialEnabled: isOneMessageTrialEnabled,
            isScreenshotDisabled: config.isScreenshotDisabled !== false,
            activeGateway: settings.activeGateway || 'razorpay',
            config: {
                isUpiEnabled: settings.isUpiEnabled !== false,
                isGooglePlayEnabled: gpSettings.isEnabled === true || settings.isGooglePlayEnabled === true,
                trialPrice: settings.trialPrice || 1,
                monthlyPrice: settings.monthlyPrice || 199
            }
        });
    } catch (e) {
        console.error("getPublicSettings Error:", e);
        res.json({ success: true, isStandardMode: false, activeGateway: 'razorpay', config: { isUpiEnabled: true, isGooglePlayEnabled: false } });
    }
};

exports.createOrder = async (req, res) => {
    try {
        let { phone, preferredGateway } = req.body;
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

exports.verifyPayment = async (req, res) => {
    try {
        let { phone } = req.body;
        if (req.user && !req.user.role) phone = req.user.phone;

        if (!phone) return res.status(400).json({ success: false, message: "Phone is required" });
        const normalizedPhone = normalize(phone);

        const io = req.app.get('socketio');
        const result = await PaymentService.verifyPayment(normalizedPhone, req.body, io);
        res.json(result);
    } catch (error) {
        console.error("Verify Payment Error:", error);
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.syncUserStatus = async (req, res) => {
    try {
        let phone = req.user?.phone || req.params.phone || req.body.phone;
        if (!phone) return res.status(401).json({ success: false, message: "Unauthorized" });

        const io = req.app.get('socketio');
        // If it's an admin request (has role), we can explicitly sync with provider
        let result;
        if (req.user?.role || req.admin) {
            result = await PaymentService.syncWithProvider(phone, io);
        } else {
            result = await PaymentService.syncUserStatus(phone);
        }

        res.json({ success: true, ...result });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.syncWithProvider = async (req, res) => {
    try {
        const phone = req.params.phone || req.body.phone;
        if (!phone) return res.status(400).json({ success: false, message: "Phone required" });

        const io = req.app.get('socketio');
        const result = await PaymentService.syncWithProvider(phone, io);
        res.json(result);
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.cancelSubscription = async (req, res) => {
    try {
        const phone = req.user?.phone;
        if (!phone) return res.status(401).json({ success: false, message: "Unauthorized" });

        const result = await PaymentService.cancelSubscription(phone);

        const io = req.app.get('socketio');
        if (io) io.to(`user_${normalize(phone)}`).emit('premium_status_refresh', { phone: phone, message: "Subscription Cancelled ⚠️", type: "warning" });

        res.json({ success: true, user: result });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.handleRazorpayWebhook = async (req, res) => {
    try {
        const signature = req.headers['x-razorpay-signature'];
        const io = req.app.get('socketio');
        await PaymentService.processWebhook('razorpay', req.body, signature, null, io);
        res.json({ status: 'ok' });
    } catch (e) {
        console.error("Razorpay Webhook Error:", e);
        res.status(200).json({ status: 'error' });
    }
};

exports.handlePhonePeWebhook = async (req, res) => {
    try {
        const signature = req.headers['x-verify'];
        const io = req.app.get('socketio');
        await PaymentService.processWebhook('phonepe', req.body, signature, null, io);
        res.json({ status: 'ok' });
    } catch (e) {
        res.status(200).json({ status: 'error' });
    }
};

exports.handleCashfreeWebhook = async (req, res) => {
    try {
        const signature = req.headers['x-cf-signature'];
        const io = req.app.get('socketio');
        await PaymentService.processWebhook('cashfree', req.body, signature, null, io);
        res.json({ status: 'ok' });
    } catch (e) {
        res.status(200).json({ status: 'error' });
    }
};

exports.handleGooglePlayWebhook = async (req, res) => {
    try {
        // Google Play RTDN (Pub/Sub) doesn't use a standard signature header like Razorpay
        // Security is usually handled by keeping the endpoint secret or IP filtering
        const io = req.app.get('socketio');
        await PaymentService.processWebhook('google_play', req.body, null, null, io);
        res.status(200).send(); // Google expects 200/204 to acknowledge receipt
    } catch (e) {
        console.error("Google Play Webhook Error:", e.message);
        res.status(200).send(); // Still return 200 to prevent Google from retrying endlessly on parse errors
    }
};

exports.broadcastStatusChange = async (req, res) => {
    try {
        const io = req.app.get('socketio');
        if (io) io.emit('premium_status_refresh', { message: "System Pricing Updated 🚀", type: "info" });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};
