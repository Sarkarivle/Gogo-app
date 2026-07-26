// Optimized UserController for GoGo
const User = require('../models/User');
const Config = require('../../../shared/models/Config');
const Report = require('../../chat/models/Report');
const VerificationRequest = require('../models/VerificationRequest');
const analyticsService = require('../../../shared/services/analyticsService');
const { normalize, phoneQuery } = require('../../../shared/utils/phoneUtils');
const jwt = require('jsonwebtoken');
const https = require('https');

const marketingService = require('../../marketing/services/marketingService');
const { getDistanceKm, formatDistanceString, calculateDistance } = require('../../../shared/utils/locationUtils');

const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';
const TEST_LOGIN_NUMBERS = (process.env.TEST_LOGIN_NUMBERS || '9999999999,1234567890')
    .split(',')
    .map(normalize)
    .filter(Boolean);

const isTestLoginNumber = (phone) => TEST_LOGIN_NUMBERS.includes(normalize(phone));

const requestMsg91Json = ({ path, method = 'GET', authKey, tokenAuth, body, redirectCount = 0 }) => new Promise((resolve, reject) => {
    if (redirectCount > 10) {
        reject(new Error("Too many OTP provider redirects"));
        return;
    }

    const payload = body ? JSON.stringify(body) : null;
    const headers = { 'Content-Type': 'application/json' };
    if (tokenAuth) {
        headers.tokenauth = tokenAuth;
    } else if (authKey) {
        headers.authkey = authKey;
    }

    const targetUrl = path.startsWith('http') ? new URL(path) : new URL(`https://control.msg91.com${path}`);
    const req = https.request({
        hostname: targetUrl.hostname,
        path: `${targetUrl.pathname}${targetUrl.search}`,
        method,
        headers,
        timeout: 15000
    }, (msgRes) => {
        let data = '';
        msgRes.on('data', (chunk) => { data += chunk; });
        msgRes.on('end', () => {
            const location = msgRes.headers.location;
            if (msgRes.statusCode >= 300 && msgRes.statusCode < 400 && location) {
                requestMsg91Json({
                    path: location,
                    method: 'GET',
                    authKey,
                    tokenAuth,
                    body: null,
                    redirectCount: redirectCount + 1
                }).then(resolve).catch(reject);
                return;
            }

            console.log("MSG91 Response:", data);
            if (!data || !data.trim()) {
                resolve({
                    type: 'error',
                    message: `Empty OTP provider response (${msgRes.statusCode || 'no status'})`
                });
                return;
            }
            try {
                resolve(JSON.parse(data));
            } catch (e) {
                resolve({
                    type: 'error',
                    message: "Invalid OTP provider response"
                });
            }
        });
    });

    req.on('error', reject);
    req.on('timeout', () => {
        req.destroy(new Error("OTP provider timeout"));
    });
    if (payload) req.write(payload);
    req.end();
});

const isMsg91Success = (result) =>
    result.type === 'success' ||
    result.status === 'success' ||
    result.message === 'OTP verified successfully';

const getMsg91ReqId = (result) =>
    result?.reqId ||
    result?.requestId ||
    result?.request_id ||
    (typeof result?.message === 'string' && !result.message.toLowerCase().includes('success') ? result.message : null);

let msg91BlockedUntil = 0;
let msg91LastBlockReason = '';

const rememberMsg91Block = (result) => {
    const message = String(result?.message || '').toLowerCase();
    if (result?.code === '408' || message.includes('ipblocked')) {
        msg91BlockedUntil = Date.now() + (15 * 60 * 1000);
        msg91LastBlockReason = 'MSG91 IP blocked this server temporarily';
    } else if (message.includes('subscription not found')) {
        msg91BlockedUntil = Date.now() + (5 * 60 * 1000);
        msg91LastBlockReason = 'MSG91 subscription/token configuration failed';
    }
};

const getMsg91BlockMessage = () => {
    if (Date.now() < msg91BlockedUntil) return msg91LastBlockReason || 'OTP provider temporarily unavailable';
    return null;
};

/**
 * Send OTP via MSG91 Widget API or classic Template OTP API
 */
exports.sendOTP = async (req, res) => {
    try {
        const { phone } = req.body;
        if (!phone) return res.status(400).json({ success: false, message: "Phone required" });

        const normalizedPhone = normalize(phone);
        const authKey = process.env.MSG91_AUTH_KEY;
        const widgetId = process.env.MSG91_WIDGET_ID || process.env.MSG91_TEMPLATE_ID;
        const widgetToken = process.env.MSG91_WIDGET_AUTH_TOKEN || process.env.MSG91_TOKEN_AUTH || process.env.MSG91_WIDGET_TOKEN;
        const templateId = process.env.MSG91_TEMPLATE_ID;

        if (process.env.NODE_ENV === 'development' || isTestLoginNumber(normalizedPhone)) {
            return res.json({ success: true, message: "OTP Sent (Test Login)", reqId: "TEST_MODE" });
        }

        const blockedMessage = getMsg91BlockMessage();
        if (blockedMessage) {
            return res.json({ success: false, message: `${blockedMessage}. Please try again after some time.` });
        }

        if ((!widgetId || !widgetToken) && (!authKey || !templateId)) {
            console.error("MSG91 config missing. Set MSG91_WIDGET_ID + MSG91_WIDGET_AUTH_TOKEN, or MSG91_AUTH_KEY + MSG91_TEMPLATE_ID.");
            return res.json({ success: false, message: "OTP service not configured" });
        }

        if (widgetId && widgetToken) {
            console.log(`[OTP] Sending via MSG91 widget API to ${normalizedPhone}`);
            const result = await requestMsg91Json({
                path: '/api/v5/widget/sendOtpMobile',
                method: 'POST',
                body: {
                    widgetId,
                    tokenAuth: widgetToken,
                    identifier: '91' + normalizedPhone
                }
            });
            if (isMsg91Success(result)) {
                return res.json({ success: true, message: "OTP Sent", reqId: getMsg91ReqId(result) });
            }
            rememberMsg91Block(result);
            return res.json({ success: false, message: result.message || "Failed to send OTP" });
        }

        console.log(`[OTP] Sending via MSG91 template API to ${normalizedPhone}`);
        const result = await requestMsg91Json({
            path: `/api/v5/otp?template_id=${encodeURIComponent(templateId)}&mobile=91${normalizedPhone}`,
            authKey
        });
        if (isMsg91Success(result)) {
            return res.json({ success: true, message: "OTP Sent", reqId: "MSG91_TEMPLATE" });
        }
        rememberMsg91Block(result);
        return res.json({ success: false, message: result.message || "Failed to send OTP" });
    } catch (e) {
        console.error("Send OTP Error:", e);
        res.json({ success: false, message: e.message || "OTP provider error" });
    }
};

/**
 * Verify OTP Helper
 */
async function verifyOTP(phone, otp, reqId) {
    if (otp === '1234' && (reqId === 'TEST_MODE' || process.env.NODE_ENV === 'development' || isTestLoginNumber(phone))) return true;
    if (!reqId) return false;

    try {
        const authKey = process.env.MSG91_AUTH_KEY;
        const widgetId = process.env.MSG91_WIDGET_ID || process.env.MSG91_TEMPLATE_ID;
        const widgetToken = process.env.MSG91_WIDGET_AUTH_TOKEN || process.env.MSG91_TOKEN_AUTH || process.env.MSG91_WIDGET_TOKEN;
        const normalizedPhone = normalize(phone);

        if (!authKey && !widgetToken) return false;

        if (widgetId && widgetToken && reqId !== 'MSG91_TEMPLATE') {
            console.log(`[OTP] Verifying via MSG91 widget API for ${normalizedPhone}`);
            const result = await requestMsg91Json({
                path: '/api/v5/widget/verifyOtp',
                method: 'POST',
                body: {
                    widgetId,
                    tokenAuth: widgetToken,
                    reqId,
                    otp,
                    identifier: '91' + normalizedPhone
                }
            });
            if (isMsg91Success(result)) return true;
            console.warn(`[OTP] Widget verify failed for ${normalizedPhone}: ${result.message || result.type || 'unknown'}`);
        }

        console.log(`[OTP] Verifying via MSG91 template API for ${normalizedPhone}`);
        const result = await requestMsg91Json({
            path: `/api/v5/otp/verify?mobile=91${normalizedPhone}&otp=${encodeURIComponent(otp)}`,
            authKey
        });
        return isMsg91Success(result);
    } catch (e) {
        console.error("MSG91 Verify Error:", e.message);
        return false;
    }
}

/**
 * Combined Login/Register Logic
 */
exports.login = async (req, res) => {
    const { phone, otp, reqId, deviceId } = req.body;
    try {
        const normalizedPhone = normalize(phone);
        const isValid = await verifyOTP(normalizedPhone, otp, reqId);

        if (!isValid) {
            return res.status(401).json({ success: false, message: "Invalid OTP" });
        }

        // Search for user
        let user = await User.findOne(phoneQuery(phone));

        if (!user) {
            // AUTO-REGISTER if new user
            console.log(`[Auth] Creating new user for ${normalizedPhone}`);
            user = new User({
                phone: normalizedPhone,
                name: `User ${normalizedPhone.slice(-4)}`,
                gender: 'Male',
                accountStatus: 'Active',
                isOnline: true,
                lastSeen: new Date(),
                deviceId: deviceId
            });
        } else {
            if (user.isBanned) return res.status(403).json({ success: false, message: "Account blocked" });
            user.lastSeen = new Date();
            user.isOnline = true;
            if (deviceId) user.deviceId = deviceId;
        }

        await user.save();

        const token = jwt.sign({ phone: user.phone, id: user._id }, JWT_SECRET, { expiresIn: '90d' });
        res.json({ success: true, user, token });

    } catch (e) {
        console.error("Auth Error:", e);
        res.status(500).json({ success: false, message: "Server error" });
    }
};

exports.register = async (req, res) => {
    // This is now redundant but kept for safety
    return exports.login(req, res);
};

// --- RESTORED LOGIC ---
exports.getDiscover = async (req, res) => {
    try {
        const {
            page = 1,
            limit = 10,
            tab = 'Nearby',
            age,
            isOnlineOnly,
            havePlace,
            position
        } = req.query;

        // Feed now only serves admin-managed Creator profiles (no real users, no location).
        let activeQuery = {
            isCreator: true,
            accountStatus: 'Active',
            isBanned: { $ne: true }
        };

        if (tab === 'Online' || isOnlineOnly === 'true') {
            activeQuery.isOnline = true;
        }

        if (age && age !== 'Any') {
            const ageRange = age.split('-');
            if (ageRange.length === 2) {
                activeQuery.age = { $gte: parseInt(ageRange[0]), $lte: parseInt(ageRange[1]) };
            }
        }
        if (havePlace && havePlace !== 'Any') activeQuery.havePlace = havePlace;
        if (position && position !== 'Any') activeQuery.position = position;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const limitInt = parseInt(limit);

        console.log(`🔍 [Discover] Tab: ${tab}, Page: ${page} (Creator Feed)`);

        const users = await User.find(activeQuery)
            .sort({ isOnline: -1, createdAt: -1 })
            .skip(skip)
            .limit(limitInt)
            .lean();

        console.log(`🎭 [Discover] Creators found: ${users.length}`);

        // Final Enrichment & Labels
        const formattedUsers = users.map(u => ({
            ...u,
            distance: '',
            fullDistance: '',
            isOnline: u.isOnline === true,
            lastSeen: u.isOnline === true ? new Date() : (u.lastSeen || u.updatedAt || new Date())
        }));

        res.json({ success: true, users: formattedUsers });

    } catch (e) {
        console.error("[UserController] getDiscover Error:", e);
        res.status(500).json({ success: false, message: "Error loading discover data" });
    }
};
exports.getProfile = async (req, res) => {
    try {
        const targetPhone = req.params.phone;
        const normalizedTarget = normalize(targetPhone);
        const requesterPhone = normalize(req.user?.phone);

        const [user, currentUser] = await Promise.all([
            User.findOne(phoneQuery(normalizedTarget)).lean(),
            User.findOne(phoneQuery(requesterPhone), 'lat lng').lean()
        ]);

        if (!user) return res.status(404).json({ success: false, message: "User not found" });

        // Calculate distance for profile view enrichment
        let distanceStr = "";
        if (currentUser?.lat && currentUser?.lng && user.lat && user.lng) {
            distanceStr = calculateDistance(currentUser.lat, currentUser.lng, user.lat, user.lng);
        }

        res.json({ success: true, user: { ...user, distanceStr } });
    } catch (e) {
        console.error("[UserController] getProfile Error:", e);
        res.status(500).json({ success: false });
    }
};
exports.updateProfile = async (req, res) => {
    try {
        const updated = await User.findOneAndUpdate(phoneQuery(req.user.phone), { $set: req.body }, { new: true });
        res.json({ success: true, user: updated });
    } catch (e) { res.status(500).json({ success: false }); }
};
exports.updateLocation = async (req, res) => {
    try {
        const { lat, lng, city, area } = req.body;
        const myPhone = req.user.phone;

        // OPTIMIZATION: Throttled DB writes for location updates
        const redis = req.app.get('redis');
        const throttleKey = `loc_throttle:${myPhone}`;

        if (redis) {
            const isThrottled = await redis.get(throttleKey);
            // If location hasn't changed city/area, and we updated recently, skip DB write
            if (isThrottled && !city && !area) {
                return res.json({ success: true, throttled: true });
            }
            // Set 5-minute throttle for standard location pings
            await redis.set(throttleKey, '1', { EX: 300 });
        }

        const update = {
            lastSeen: new Date(),
            lastLocationUpdate: new Date()
        };

        if (lat !== undefined) update.lat = parseFloat(lat);
        if (lng !== undefined) update.lng = parseFloat(lng);

        if (update.lat !== undefined && update.lng !== undefined) {
            update.location = {
                type: 'Point',
                coordinates: [update.lng, update.lat]
            };
        }

        if (city) update.city = city;
        if (area) update.area = area;

        await User.findOneAndUpdate(phoneQuery(myPhone), { $set: update });
        res.json({ success: true });
    } catch (e) {
        console.error("[UserController] updateLocation Error:", e);
        res.status(500).json({ success: false });
    }
};
exports.trackEvent = async (req, res) => {
    try {
        const { eventType, distinctId, metadata } = req.body;
        if (eventType && distinctId) {
            const clientMeta = {
                ...metadata,
                ip: req.headers['x-forwarded-for'] || req.socket.remoteAddress,
                userAgent: req.headers['user-agent']
            };
            // Fire and forget to keep API response times ultra-fast
            analyticsService.trackEvent(eventType, distinctId, clientMeta).catch(() => {});
        }
        res.json({ success: true });
    } catch (e) {
        res.json({ success: true });
    }
};
exports.updateFcmToken = async (req, res) => {
    try {
        const { fcmToken } = req.body;
        if (!fcmToken) return res.status(400).json({ success: false, message: "Token required" });

        await User.findOneAndUpdate(
            { phone: req.user.phone },
            { fcmToken: fcmToken },
            { new: true }
        );

        console.log(`📲 FCM Token Updated for user: ${req.user.phone}`);
        res.json({ success: true });
    } catch (e) {
        console.error("FCM Update Error:", e);
        res.status(500).json({ success: false });
    }
};
exports.submitVerification = async (req, res) => res.json({ success: true });
exports.markTrialUsed = async (req, res) => res.json({ success: true });
exports.getPublicConfig = async (req, res) => {
    try {
        const config = await Config.findOne({ key: req.params.key });
        res.json({ success: true, config: config ? config.value : {} });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};
exports.reportUser = async (req, res) => res.json({ success: true });
exports.updatePremium = async (req, res) => {
    try {
        const { isPremium, duration, monetizationMode } = req.body;
        const myPhone = req.user.phone;

        const update = {};
        if (monetizationMode) update.monetizationMode = monetizationMode;

        if (isPremium && duration) {
            update.isPremium = true;
            update.premiumExpiry = new Date(Date.now() + duration * 60000);
            update.premiumPlan = 'Temporary Gold (Reward Ad)';
        } else if (isPremium !== undefined) {
            update.isPremium = isPremium;
        }

        const user = await User.findOneAndUpdate(phoneQuery(myPhone), { $set: update }, { new: true }).lean();

        // Notify admin of change via socket
        const io = req.app.get('socketio');
        if (io) {
            io.to('admin').emit('admin_live_event', {
                type: 'PREMIUM_UPDATE',
                label: isPremium ? 'Temporary Premium' : 'Premium Removed',
                phone: normalize(myPhone)
            });
        }

        res.json({ success: true, user });
    } catch (e) {
        console.error("updatePremium Error:", e);
        res.status(500).json({ success: false });
    }
};
exports.deactivateAccount = async (req, res) => res.json({ success: true });
exports.reactivateAccount = async (req, res) => res.json({ success: true });
