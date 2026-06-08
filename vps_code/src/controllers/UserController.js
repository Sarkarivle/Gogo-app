// Optimized UserController for GoGo
const User = require('../models/User');
const Config = require('../models/Config');
const Report = require('../models/Report');
const VerificationRequest = require('../models/VerificationRequest');
const analyticsService = require('../services/analyticsService');
const { normalize, phoneQuery } = require('../utils/phoneUtils');
const jwt = require('jsonwebtoken');
const admin = require('firebase-admin');

const marketingService = require('../services/marketingService');

const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

/**
 * Helper to verify Firebase ID Token
 */
async function verifyFirebaseToken(phone, token) {
    if (process.env.NODE_ENV === 'development' && !token) return true; // Bypass for dev if needed
    if (!token) return false;
    try {
        const decodedToken = await admin.auth().verifyIdToken(token);
        const firebasePhone = normalize(decodedToken.phone_number);
        const requestPhone = normalize(phone);
        return firebasePhone === requestPhone;
    } catch (error) {
        console.error("Firebase Verification Error:", error.message);
        return false;
    }
}

/**
 * Helper to calculate numeric distance in KM
 */
function getDistanceKm(lat1, lon1, lat2, lon2) {
    try {
        const p1Lat = parseFloat(lat1);
        const p1Lon = parseFloat(lon1);
        const p2Lat = parseFloat(lat2);
        const p2Lon = parseFloat(lon2);
        if (isNaN(p1Lat) || isNaN(p1Lon) || isNaN(p2Lat) || isNaN(p2Lon)) return null;

        const R = 6371;
        const dLat = (p2Lat - p1Lat) * Math.PI / 180;
        const dLon = (p2Lon - p1Lon) * Math.PI / 180;
        const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                  Math.cos(p1Lat * Math.PI / 180) * Math.cos(p2Lat * Math.PI / 180) *
                  Math.sin(dLon / 2) * Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    } catch (e) { return null; }
}

/**
 * Helper to format distance string
 */
function formatDistanceString(d) {
    if (d === null) return "";
    if (d < 0.5) return "0.5 km";
    if (d < 1) return "Within 1 km";
    if (d < 5) return "Under 5 km";
    return d.toFixed(1) + " km";
}

/**
 * Legacy helper for other controllers if needed
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
    return formatDistanceString(getDistanceKm(lat1, lon1, lat2, lon2));
}

exports.submitVerification = async (req, res) => {
    try {
        let phone = req.body.phone;
        // Security: Use phone from token for users
        if (req.user && !req.user.role) phone = req.user.phone;
        const { selfieUrl } = req.body;
        const normalizedPhone = normalize(phone);
        await VerificationRequest.findOneAndUpdate(
            { userPhone: normalizedPhone },
            { selfieUrl, status: 'Pending', submittedAt: new Date() },
            { upsert: true }
        );
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.updateFcmToken = async (req, res) => {
    try {
        // Use phone from token for security, fallback to body only if Admin
        const phone = (req.user && !req.user.role) ? req.user.phone : req.body.phone;
        const normalizedPhone = normalize(phone);
        const { fcmToken } = req.body;
        await User.findOneAndUpdate(phoneQuery(normalizedPhone), { fcmToken });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

/**
 * Helper to sync premium status based on review mode and expiry
 */
async function syncUserStatus(user, isStandardMode) {
    let changed = false;
    const now = new Date();

    // Ensure 1-message trial flag exists
    if (user.oneMessageTrialUsed === undefined) {
        user.oneMessageTrialUsed = false;
        changed = true;
    }

    // 1. Manage 'Standard Access' users (Google Compliance Mode)
    if (user.premiumPlan === 'Standard Access') {
        if (!isStandardMode) {
            // Toggle is OFF -> Remove Standard Access completely
            user.isPremium = false;
            user.premiumPlan = 'None';
            changed = true;
        } else if (user.isPremium) {
            // Toggle is ON -> Set isPremium=false (App logic will show as Freemium)
            user.isPremium = false;
            changed = true;
        }
    }

    // 2. Auto-downgrade if premium expired (for real paid users)
    if (user.isPremium) {
        if (!user.premiumExpiry || new Date(user.premiumExpiry) < now) {
            user.isPremium = false;
            if (user.subscription) user.subscription.status = 'expired';
            changed = true;
        }
    }

    if (changed && user.save) {
        await User.updateOne({ _id: user._id }, {
            $set: {
                isPremium: user.isPremium,
                premiumPlan: user.premiumPlan,
                premiumExpiry: user.premiumExpiry,
                'subscription.status': user.subscription?.status
            }
        });
    }
    return user;
}

exports.getProfile = async (req, res) => {
    try {
        const phone = req.params.phone;
        const [user, reviewConfig] = await Promise.all([
            User.findOne(phoneQuery(phone)).select('-lat -lng -location').lean(),
            Config.findOne({ key: 'review_mode_config' })
        ]);

        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        const isStandardMode = reviewConfig?.value?.isReviewMode === true;
        await syncUserStatus(user, isStandardMode);

        const cleanArea = (user.area && user.area.toLowerCase() !== 'unknown') ? user.area : '';
        const cleanCity = (user.city && user.city.toLowerCase() !== 'unknown') ? user.city : '';

        user.cityLabel = cleanArea || cleanCity || 'Nearby';
        user.area = '';

        res.json({ success: true, user, isStandardMode });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.markTrialUsed = async (req, res) => {
    try {
        const phone = req.user?.phone;
        if (!phone) return res.status(401).json({ success: false });

        const User = require('../models/User');
        await User.findOneAndUpdate(phoneQuery(phone), { oneMessageTrialUsed: true });

        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.login = async (req, res) => {
    const { phone, firebaseToken, deviceId, deviceModel, os, ip } = req.body;
    try {
        const normalizedPhone = normalize(phone);
        const isValid = await verifyFirebaseToken(normalizedPhone, firebaseToken);
        if (!isValid) {
            return res.status(401).json({ success: false, message: "Identity verification failed" });
        }

        const [user, reviewConfig] = await Promise.all([
            User.findOne(phoneQuery(phone)),
            Config.findOne({ key: 'review_mode_config' })
        ]);

        const isStandardMode = reviewConfig?.value?.isReviewMode === true;

        if (user) {
            if (user.accountStatus === 'Suspended' || user.accountStatus === 'Banned' || user.isBanned) {
                return res.status(403).json({ success: false, message: "Account blocked" });
            }
            if (user.isDeactivated || user.accountStatus === 'Deactivated') {
                user.isDeactivated = false;
                user.accountStatus = 'Active';
                user.reactivatedAt = new Date();
            }
            user.lastSeen = new Date();
            user.isOnline = true;

            await syncUserStatus(user, isStandardMode);

            if (deviceId) user.deviceId = deviceId;
            if (ip) user.ipAddress = ip;

            if (deviceId) {
                const deviceExists = user.deviceHistory.find(d => d.deviceId === deviceId);
                if (deviceExists) {
                    deviceExists.lastUsed = new Date();
                } else {
                    user.deviceHistory.push({ deviceId, model: deviceModel, os, ip, lastUsed: new Date() });
                }
            }
            await user.save();
            const token = jwt.sign({ phone: user.phone, id: user._id }, JWT_SECRET, { expiresIn: '90d' });
            res.json({ success: true, user, token, isStandardMode });
        } else {
            res.json({ success: false, isStandardMode });
        }
    } catch (e) {
        res.status(500).json({ success: false, error: "Internal Server Error" });
    }
};

exports.getPublicConfig = async (req, res) => {
    try {
        const { key } = req.params;
        const allowedKeys = ['app_update_config', 'review_mode_config'];
        if (!allowedKeys.includes(key)) return res.status(403).json({ success: false });

        const config = await Config.findOne({ key });
        res.json({ success: true, config: config ? config.value : {} });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.reportUser = async (req, res) => {
    try {
        let { reporterPhone, reportedPhone, category, description, reportType } = req.body;
        // Security: Ensure reporter is the logged-in user
        if (req.user && !req.user.role) reporterPhone = req.user.phone;

        const report = new Report({
            reporterPhone: normalize(reporterPhone),
            reportedPhone: normalize(reportedPhone),
            category,
            description,
            reportType: reportType || 'Profile Report'
        });
        await report.save();
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.register = async (req, res) => {
    let { phone, name, gender, firebaseToken } = req.body;
    if (!phone) return res.status(400).json({ success: false, message: "Phone required" });

    const normalizedPhone = normalize(phone);
    const isValid = await verifyFirebaseToken(normalizedPhone, firebaseToken);
    if (!isValid) {
        return res.status(401).json({ success: false, message: "Identity verification failed" });
    }

    try {
        const [existing, reviewConfig] = await Promise.all([
            User.findOne(phoneQuery(phone)),
            Config.findOne({ key: 'review_mode_config' })
        ]);

        const isStandardMode = reviewConfig?.value?.isReviewMode === true;

        if (existing) {
            await syncUserStatus(existing, isStandardMode);
            const token = jwt.sign({ phone: existing.phone, id: existing._id }, JWT_SECRET, { expiresIn: '90d' });
            return res.json({ success: true, user: existing, token, isStandardMode });
        }

        const userData = {
            phone: normalizedPhone,
            name: name || 'GoGo User',
            gender: gender || 'Male',
            dobDay: req.body.dobDay,
            dobMonth: req.body.dobMonth,
            dobYear: req.body.dobYear,
            bio: req.body.bio,
            accountStatus: 'Active',
            isBanned: false,
            isDeactivated: false,
            isOnline: true,
            lastSeen: new Date(),
            isPremium: false,
            premiumPlan: 'None',
            premiumExpiry: null
        };

        if (userData.dobYear) {
            const year = parseInt(userData.dobYear);
            if (!isNaN(year)) userData.age = new Date().getFullYear() - year;
        }

        const newUser = new User(userData);
        const savedUser = await newUser.save();

        analyticsService.trackEvent('registration', normalizedPhone);
        marketingService.triggerS2SPostback('registration', req.body.clickId);

        const token = jwt.sign({ phone: savedUser.phone, id: savedUser._id }, JWT_SECRET, { expiresIn: '90d' });
        res.json({ success: true, user: savedUser, token, isStandardMode: isStandardMode });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.updateLocation = async (req, res) => {
    try {
        let { phone, lat, lng, city, area } = req.body;
        // Identity check: Always prefer token phone for users
        if (req.user && !req.user.role) phone = req.user.phone;

        if (city && city.toLowerCase() === 'unknown') city = null;
        if (area && area.toLowerCase() === 'unknown') area = null;
        const update = { lastSeen: new Date() };
        if (lat) update.lat = lat;
        if (lng) update.lng = lng;
        if (city) update.city = city;
        if (area) update.area = area;
        if (lat && lng) {
            update.location = { type: 'Point', coordinates: [parseFloat(lng), parseFloat(lat)] };
        }
        await User.findOneAndUpdate(phoneQuery(phone), { $set: update });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.updateProfile = async (req, res) => {
    try {
        let { phone, ...updateData } = req.body;
        // Identity check: Always prefer token phone for users
        if (req.user && !req.user.role) phone = req.user.phone;

        // SECURE: Prevent Mass Assignment (Privilege Escalation)
        const allowedUpdates = [
            'name', 'bio', 'gender', 'age', 'dobDay', 'dobMonth', 'dobYear',
            'position', 'havePlace', 'heightFt', 'heightInch', 'weight',
            'profileImages', 'hasCompletedOnboarding'
        ];

        const filteredUpdate = {};
        allowedUpdates.forEach(key => {
            if (updateData[key] !== undefined) filteredUpdate[key] = updateData[key];
        });

        if (filteredUpdate.dobYear) {
            const year = parseInt(filteredUpdate.dobYear);
            if (!isNaN(year)) filteredUpdate.age = new Date().getFullYear() - year;
        }
        filteredUpdate.lastSeen = new Date();

        const updatedUser = await User.findOneAndUpdate(phoneQuery(phone), { $set: filteredUpdate }, { new: true });
        if (!updatedUser) return res.status(404).json({ success: false });
        if (filteredUpdate.hasCompletedOnboarding) analyticsService.trackEvent('onboarding_completed', normalize(phone));
        res.json({ success: true, user: updatedUser });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.updatePremium = async (req, res) => {
    try {
        // Security: This route should ONLY be callable by admins.
        // Regular users must go through PaymentController / Webhooks.
        if (req.user && !req.user.role) {
            return res.status(403).json({ success: false, message: "Unauthorized. Use payment gateway." });
        }

        const { phone, isPremium } = req.body;
        const updatedUser = await User.findOneAndUpdate(phoneQuery(phone), { isPremium, lastSeen: new Date() }, { new: true });
        res.json({ success: true, user: updatedUser });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.getDiscover = async (req, res) => {
    try {
        const { page = 1, limit = 10, tab = 'Nearby', distance, age, isOnlineOnly, havePlace, position, lat, lng } = req.query;
        let phone = (req.user && !req.user.role) ? req.user.phone : req.query.phone;
        const normalizedPhone = normalize(phone);

        console.log(`🔍 Discover Fetch: User=${normalizedPhone}, Tab=${tab}, Page=${page}`);

        let userLat = lat ? parseFloat(lat) : null;
        let userLng = lng ? parseFloat(lng) : null;
        if (!userLat || !userLng) {
            const caller = await User.findOne(phoneQuery(normalizedPhone), 'lat lng location').lean();
            if (caller) {
                userLat = caller.lat || caller.location?.coordinates?.[1];
                userLng = caller.lng || caller.location?.coordinates?.[0];
            }
        }
        const pageNum = Math.max(1, parseInt(page));
        const limitNum = Math.max(1, parseInt(limit));
        const skip = (pageNum - 1) * limitNum;

        // --- REDIS CACHING (30s TTL) for Discovery ---
        const redis = req.app.get('redis');

        // Location-aware cache key for Nearby to avoid inconsistency
        let locationSegment = 'global';
        if (tab === 'Nearby' && typeof userLat === 'number' && typeof userLng === 'number' && !isNaN(userLat)) {
            // Round to ~1km precision to allow some caching benefits without showing far away data
            locationSegment = `${userLat.toFixed(2)}_${userLng.toFixed(2)}`;
        }

        const cacheKey = `discover:${tab}:${locationSegment}:${distance || 'any'}:${age || 'any'}:${position || 'any'}:${havePlace || 'any'}:${isOnlineOnly || 'false'}:${page}`;

        if (redis && page <= 5) { // Increased cache pages
            const cachedData = await redis.get(cacheKey);
            if (cachedData) {
                return res.json(JSON.parse(cachedData));
            }
        }

        // Exclude caller and incomplete profiles
        const phoneVariations = [normalizedPhone, `+91${normalizedPhone}`, `91${normalizedPhone}`];

        // A profile is complete if hasCompletedOnboarding is true OR they have basic info filled (for old users)
        const baseQuery = {
            phone: { $nin: phoneVariations },
            accountStatus: 'Active',
            $or: [
                { hasCompletedOnboarding: true },
                { dobYear: { $exists: true, $ne: null } }
            ]
        };

        const io = req.app.get('socketio');

        if (tab === 'Online') {
            if (redis) {
                // EXTREME SPEED: Fetch current online phones from Redis
                try {
                    const onlinePhones = await redis.sMembers('online_users');
                    console.log(`🌐 Redis Online Users Count: ${onlinePhones.length}`);
                    if (onlinePhones.length > 0) {
                        const searchVariations = onlinePhones.reduce((acc, p) => {
                            const n = normalize(p);
                            acc.push(n, `+91${n}`, `91${n}`);
                            return acc;
                        }, []);
                        // IMPORTANT: Still need to filter out the caller and ensure they are active/complete
                        baseQuery.phone = { $in: searchVariations, $nin: phoneVariations };
                    } else {
                        // If Redis is empty (server restart?), fallback to DB isOnline field
                        baseQuery.isOnline = true;
                    }
                } catch (err) {
                    console.error("Redis Online Fetch Error:", err.message);
                    baseQuery.isOnline = true;
                }
            } else {
                baseQuery.isOnline = true;
            }
        }
 else if (isOnlineOnly === 'true') {
            baseQuery.isOnline = true;
        }

        if (havePlace && havePlace !== 'Any') baseQuery.havePlace = havePlace;
        if (position && position !== 'Any') {
            const searchTerms = position.split(',').map(p => p.trim()).filter(p => p);
            if (searchTerms.length > 0) {
                // Optimized: Use $in for exact matches or prefix matching if possible.
                // Case-insensitive exact match is better than full regex.
                const posQuery = { position: { $in: searchTerms } };
                if (baseQuery.$or) {
                    const existingOr = baseQuery.$or;
                    delete baseQuery.$or;
                    baseQuery.$and = [{ $or: existingOr }, posQuery];
                } else if (baseQuery.$and) {
                    baseQuery.$and.push(posQuery);
                } else {
                    baseQuery.position = posQuery.position;
                }
            }
        }
        if (age && age !== 'Any') {
            const ageMap = { '18-25': { $gte: 18, $lte: 25 }, '26-35': { $gte: 26, $lte: 35 }, '36-45': { $gte: 36, $lte: 45 }, '46+': { $gte: 46 } };
            if (ageMap[age]) baseQuery.age = ageMap[age];
        }

        let users = [];
        if (tab === 'Nearby' && typeof userLat === 'number' && typeof userLng === 'number') {
            let maxDist = 300 * 1000; // Default: 300km (0 to 300km)

            // Apply distance filter ONLY if explicitly requested and not 'Any'
            // We ignore common app defaults like '50km' if it's the first load/default state
            // But to be safe, we'll check if distance is provided and not 'Any'
            if (distance && distance !== 'Any') {
                const requestedDist = parseInt(distance.replace('km', ''));
                // If the app sends a distance but we want 300km default,
                // we only apply it if it's not the 'standard' starting distance
                // OR we just trust the 'Any' logic from the frontend.
                if (!isNaN(requestedDist)) {
                    maxDist = requestedDist * 1000;
                }
            }

            // Using $near requires a 2dsphere index on the 'location' field
            // It automatically sorts by distance from 0km to maxDist
            try {
                users = await User.find({
                    ...baseQuery,
                    location: {
                        $near: {
                            $geometry: { type: "Point", coordinates: [userLng, userLat] },
                            $maxDistance: maxDist
                        }
                    }
                })
                .select('name phone gender age profileImages city area lat lng location position havePlace isOnline isVerified isPremium chatCount hasCompletedOnboarding accountStatus isDeactivated')
                .skip(skip)
                .limit(limitNum)
                .lean();
            } catch (queryErr) {
                console.error("MongoDB $near Error:", queryErr.message);
                // Fallback to regular query if $near fails (e.g. missing index)
                users = await User.find(baseQuery)
                    .select('name phone gender age profileImages city area lat lng location position havePlace isOnline isVerified isPremium chatCount hasCompletedOnboarding accountStatus isDeactivated')
                    .sort({ lastSeen: -1 })
                    .skip(skip)
                    .limit(limitNum)
                    .lean();
            }
        } else {
            let sort = { lastSeen: -1 };
            if (tab === 'New') {
                sort = { createdAt: -1 };
            } else if (tab === 'Popular') {
                sort = { chatCount: -1, lastSeen: -1 };
            }
            users = await User.find(baseQuery)
                .select('name phone gender age profileImages city area lat lng location position havePlace isOnline isVerified isPremium chatCount hasCompletedOnboarding accountStatus isDeactivated')
                .sort(sort)
                .skip(skip)
                .limit(limitNum)
                .lean();
        }

        console.log(`✅ Discovery Found: ${users.length} users`);

        // Fetch real-time online status from Redis for all displayed users
        let onlineSet = new Set();
        if (redis) {
            try {
                const onlinePhones = await redis.sMembers('online_users');
                onlinePhones.forEach(p => onlineSet.add(normalize(p)));
            } catch (err) {}
        }

        const processedUsers = users.map(u => {
            const uLat = u.lat || u.location?.coordinates?.[1];
            const uLng = u.lng || u.location?.coordinates?.[0];

            let distStr = "";
            if (userLat && userLng && uLat && uLng) {
                // Calculate distance again to apply display rules
                const d = getDistanceKm(userLat, userLng, uLat, uLng);
                // Rule: On Home Page (Discovery), hide distance if > 20km for privacy
                // This applies to ALL tabs (Nearby, Online, etc.) on the home page.
                if (d > 20) {
                    distStr = "";
                } else {
                    distStr = formatDistanceString(d);
                }
            }

            const cleanArea = (u.area && u.area.toLowerCase() !== 'unknown') ? u.area : '';
            const cleanCity = (u.city && u.city.toLowerCase() !== 'unknown') ? u.city : '';

            // REALTIME STATUS: Use Redis set if available, fallback to DB isOnline field
            let isOnline = u.isOnline;
            if (onlineSet.size > 0) {
                isOnline = onlineSet.has(normalize(u.phone));
            }

            const { lat, lng, location, ...rest } = u;
            return { ...rest, isOnline, city: cleanArea || cleanCity || 'Nearby', area: '', distance: distStr };
        });

        const resultPayload = { success: true, page: pageNum, users: processedUsers };

        if (redis && page <= 3) {
            await redis.setEx(cacheKey, 30, JSON.stringify(resultPayload));
        }

        res.json(resultPayload);
    } catch (e) {
        res.status(500).json({ success: false, users: [] });
    }
};

exports.trackEvent = async (req, res) => {
    try {
        const { eventType, distinctId, metadata } = req.body;
        const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
        const userAgent = req.headers['user-agent'];

        if (eventType) {
            analyticsService.trackEvent(eventType, distinctId, {
                ...metadata,
                ip,
                userAgent
            });
        }
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.deactivateAccount = async (req, res) => {
    try {
        let { phone, reason } = req.body;
        // IDOR Prevention: Always prefer token phone for users
        if (req.user && !req.user.role) phone = req.user.phone;

        const user = await User.findOne(phoneQuery(phone));
        if (!user) return res.status(404).json({ success: false });
        user.isDeactivated = true;
        user.accountStatus = 'Deactivated';
        user.deactivatedAt = new Date();
        user.isOnline = false;
        await user.save();
        const io = req.app.get('socketio');
        if (io) io.emit('user_deactivated', { phone: user.phone });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.reactivateAccount = async (req, res) => {
    try {
        let { phone } = req.body;
        // IDOR Prevention: Always prefer token phone for users
        if (req.user && !req.user.role) phone = req.user.phone;

        const [user, reviewConfig] = await Promise.all([
            User.findOne(phoneQuery(phone)),
            Config.findOne({ key: 'review_mode_config' })
        ]);

        if (!user) return res.status(404).json({ success: false });

        const isStandardMode = reviewConfig?.value?.isReviewMode === true;

        user.isDeactivated = false;
        user.accountStatus = 'Active';
        user.reactivatedAt = new Date();
        user.isOnline = true;

        await syncUserStatus(user, isStandardMode);

        const io = req.app.get('socketio');
        if (io) io.emit('user_reactivated', { phone: user.phone });
        res.json({ success: true, user, isStandardMode });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

