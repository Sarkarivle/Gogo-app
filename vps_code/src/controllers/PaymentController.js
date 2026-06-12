const PaymentService = require('../services/payment/PaymentService');
const Config = require('../models/Config');
const User = require('../models/User'); // Import at top
const { normalize } = require('../utils/phoneUtils');
const jwt = require('jsonwebtoken');
const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

exports.getPublicSettings = async (req, res) => {
    try {
        const [payConfig, gpConfig, reviewConfig] = await Promise.all([
            Config.findOne({ key: 'payment_settings' }),
            Config.findOne({ key: 'google_play_settings' }),
            Config.findOne({ key: 'review_mode_config' })
        ]);

        const settings = payConfig?.value || {};
        const gpSettings = gpConfig?.value || {};

        // OPTIMIZATION: Extract user info from token without hitting DB (it's only used for logging)
        let userId = 'Guest';
        const authHeader = req.headers.authorization;
        if (authHeader && authHeader.startsWith('Bearer ')) {
            try {
                const token = authHeader.split(' ')[1];
                const decoded = jwt.verify(token, JWT_SECRET);
                if (decoded && decoded.phone) {
                    userId = decoded.phone;
                }
            } catch (err) {
                // Ignore invalid tokens
            }
        }

        const config = reviewConfig?.value || {};

        // Trial logic: Trial is only allowed if global trial is enabled
        let isOneMessageTrialEnabled = config.isOneMessageTrialEnabled === true;

        console.log(`🛡️ Compliance: User=${userId}, Trial=${isOneMessageTrialEnabled}`);

        res.json({
            success: true,
            isOneMessageTrialEnabled: isOneMessageTrialEnabled,
            isScreenshotDisabled: config.isScreenshotDisabled !== false,
            activeGateway: settings.activeGateway || 'razorpay',
            buildVersion: "1.0.2-multi-id-fix", // Added to verify deployment
            config: {
                isUpiEnabled: settings.isUpiEnabled !== false,
                isGooglePlayEnabled: gpSettings.isEnabled === true || settings.isGooglePlayEnabled === true,
                trialPrice: settings.trialPrice || 1,
                trialDuration: settings.trialDuration || 1,
                monthlyPrice: settings.monthlyPrice || 199
            }
        });
    } catch (e) {
        console.error("getPublicSettings Error:", e);
        res.json({ success: true, activeGateway: 'razorpay', config: { isUpiEnabled: true, isGooglePlayEnabled: false } });
    }
};

exports.getReviewModeConfig = async (req, res) => {
    try {
        const config = await Config.findOne({ key: 'review_mode_config' });
        res.json({
            success: true,
            config: config?.value || {
                isOneMessageTrialEnabled: false,
                isScreenshotDisabled: true
            }
        });
    } catch (e) {
        res.json({ success: false, message: e.message });
    }
};

exports.getAdsSettings = async (req, res) => {
    try {
        const config = await Config.findOne({ key: 'ads_settings' });
        res.json({
            success: true,
            config: config?.value || {
                isEnabled: false,
                freeUsersOnly: true,
                activeProvider: 'google',
                frequencyMinutes: 5,
                google: {
                    bannerId: '',
                    interstitialId: '',
                    rewardedId: '',
                    nativeId: ''
                }
            }
        });
    } catch (e) {
        res.json({ success: false, message: e.message });
    }
};

exports.getSpecialOffers = async (req, res) => {
    try {
        const config = await Config.findOne({ key: 'special_offers' });

        const defaultOffers = [
            { id: 'monthly', name: '1 Month Premium', price: 199, duration: 30, rzpPlanId: '', googlePlayId: '', googlePlaySubId: '' }
        ];

        let resultConfig = config?.value || { offers: defaultOffers };

        // Logic Change: Only return ONE offer (the first one) to simplify frontend to "Single Offer" mode
        if (resultConfig.offers && Array.isArray(resultConfig.offers) && resultConfig.offers.length > 0) {
            resultConfig.offers = [resultConfig.offers[0]]; // Take only the primary offer
        } else {
            resultConfig.offers = defaultOffers;
        }

        res.json({
            success: true,
            buildVersion: "1.1.0-single-offer-logic",
            config: resultConfig
        });
    } catch (e) {
        console.error("getSpecialOffers Error:", e);
        res.json({ success: false, message: e.message });
    }
};

exports.createOrder = async (req, res) => {
    try {
        let { phone, preferredGateway, amount, offerId, googlePlayId, googlePlaySubId, duration } = req.body;
        if (req.user && !req.user.role) phone = req.user.phone;

        if (!phone) return res.status(400).json({ success: false, message: "Phone is required" });
        const normalizedPhone = normalize(phone);

        const orderData = await PaymentService.createOrder(normalizedPhone, preferredGateway, { amount, offerId, googlePlayId, googlePlaySubId, duration });
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

        // Real-time: Sync with provider for EVERYONE when they check status
        // This ensures Next Bill Date and Auto-Renew status are always accurate from Gateway
        let result;
        try {
            const syncResult = await PaymentService.syncWithProvider(phone, io);
            const statusResult = await PaymentService.syncUserStatus(phone);
            result = {
                ...statusResult,
                user: syncResult.user,
                subscription: syncResult.user.subscription,
                paymentHistory: (syncResult.user.paymentHistory || []).slice(-10)
            };
        } catch (syncErr) {
            console.error("Provider sync failed, falling back to DB:", syncErr.message);
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
