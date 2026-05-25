const User = require('../models/User');
const Report = require('../models/Report');
const VerificationRequest = require('../models/VerificationRequest');
const analyticsService = require('../services/analyticsService');

/**
 * Helper to calculate distance for privacy
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
    const p1Lat = parseFloat(lat1);
    const p1Lon = parseFloat(lon1);
    const p2Lat = parseFloat(lat2);
    const p2Lon = parseFloat(lon2);

    // Check if any coordinate is missing or essentially zero
    if (!p1Lat || !p1Lon || !p2Lat || !p2Lon) return "";

    const R = 6371; // km
    const dLat = (p2Lat - p1Lat) * Math.PI / 180;
    const dLon = (p2Lon - p1Lon) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(p1Lat * Math.PI / 180) * Math.cos(p2Lat * Math.PI / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const d = R * c;

    // Estimated distance labels for privacy
    if (d < 1) return "Within 1 km";
    return `${d.toFixed(1)} km`;
}

exports.submitVerification = async (req, res) => {
    try {
        const { phone, selfieUrl } = req.body;
        await VerificationRequest.findOneAndUpdate(
            { userPhone: phone },
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
        const { phone, fcmToken } = req.body;
        await User.findOneAndUpdate({ phone }, { fcmToken });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.getProfile = async (req, res) => {
    try {
        const user = await User.findOne({ phone: req.params.phone }).select('-lat -lng -location').lean();
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        // Smart Location Label: Best single name (Area or City)
        const cleanArea = (user.area && user.area.toLowerCase() !== 'unknown') ? user.area : '';
        const cleanCity = (user.city && user.city.toLowerCase() !== 'unknown') ? user.city : '';

        user.city = cleanArea || cleanCity || 'Nearby';
        user.area = '';

        res.json({ success: true, user });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.login = async (req, res) => {
    const { phone, deviceId, deviceModel, os, ip } = req.body;
    console.log(`[LOGIN_INVOKED] Phone: ${phone}`);
    try {
        console.log(`[DB_LOOKUP] Searching for user: ${phone}`);
        const user = await User.findOne({ phone });

        if (user) {
            console.log(`[DB_FOUND] User ID: ${user._id}`);
            if (user.accountStatus === 'Suspended' || user.accountStatus === 'Banned' || user.isBanned) {
                console.warn(`[AUTH_BLOCKED] User ${phone} is blocked.`);
                return res.status(403).json({ success: false, message: "Account blocked by moderator" });
            }

            // Handle Auto-Reactivation
            if (user.isDeactivated || user.accountStatus === 'Deactivated') {
                console.log(`[REACTIVATION] User ${phone} reactivating.`);
                user.isDeactivated = false;
                user.accountStatus = 'Active';
                user.reactivatedAt = new Date();

                // Notify system/realtime if needed (will be handled by socket on set_online)
            }

            // Update Security Tracking
            user.lastSeen = new Date();
            user.isOnline = true;
            if (deviceId) user.deviceId = deviceId;
            if (ip) user.ipAddress = ip;

            // Add to device history
            if (deviceId) {
                const deviceExists = user.deviceHistory.find(d => d.deviceId === deviceId);
                if (deviceExists) {
                    deviceExists.lastUsed = new Date();
                    deviceExists.ip = ip || deviceExists.ip;
                } else {
                    user.deviceHistory.push({ deviceId, model: deviceModel, os, ip, lastUsed: new Date() });
                }
            }

            await user.save();
            console.log(`[AUTH_SUCCESS] User ${phone} logged in.`);
            res.json({ success: true, user });
        } else {
            console.log(`[DB_MISS] User ${phone} not found.`);
            res.json({ success: false });
        }
    } catch (e) {
        console.error(`[LOGIN_FATAL] Error for ${phone}:`, e);
        res.status(500).json({ success: false, error: "Internal Server Error" });
    }
};

exports.reportUser = async (req, res) => {
    try {
        const { reporterPhone, reportedPhone, category, description, reportType } = req.body;
        const report = new Report({
            reporterPhone,
            reportedPhone,
            category,
            description,
            reportType: reportType || 'Profile Report'
        });
        await report.save();
        res.json({ success: true, message: "Report submitted" });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.register = async (req, res) => {
    const { phone } = req.body;
    console.log(`[REGISTER_INVOKED] Data:`, JSON.stringify(req.body));
    try {
        // Double check existence
        const existing = await User.findOne({ phone });
        if (existing) {
            console.log(`[REGISTER_CONFLICT] User ${phone} already exists. Returning profile.`);
            return res.json({ success: true, user: existing });
        }

        const newUser = new User(req.body);
        const savedUser = await newUser.save();
        console.log(`[REGISTER_SUCCESS] Created user ${phone} with ID: ${savedUser._id}`);
        res.json({ success: true, user: savedUser });
    } catch (e) {
        console.error(`[REGISTER_FATAL] Error for ${phone}:`, e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.updateLocation = async (req, res) => {
    try {
        let { phone, lat, lng, city, area } = req.body;

        // Clean up "Unknown" strings sent from mobile
        if (city && city.toLowerCase() === 'unknown') city = null;
        if (area && area.toLowerCase() === 'unknown') area = null;

        const update = { lastSeen: new Date() };
        if (lat) update.lat = lat;
        if (lng) update.lng = lng;
        if (city) update.city = city;
        if (area) update.area = area;

        if (lat && lng) {
            update.location = {
                type: 'Point',
                coordinates: [parseFloat(lng), parseFloat(lat)]
            };
        }

        await User.findOneAndUpdate({ phone }, { $set: update });
        res.json({ success: true });
    } catch (e) {
        console.error("UPDATE_LOCATION_ERROR:", e);
        res.status(500).json({ success: false });
    }
};

exports.updateProfile = async (req, res) => {
    try {
        const { phone, ...updateData } = req.body;

        // Calculate age if dobYear is provided
        if (updateData.dobYear) {
            const currentYear = new Date().getFullYear();
            const year = parseInt(updateData.dobYear);
            if (!isNaN(year)) {
                updateData.age = currentYear - year;
            }
        }

        updateData.lastSeen = new Date();
        const updatedUser = await User.findOneAndUpdate(
            { phone },
            { $set: updateData }, // Using $set to ensure only provided fields are updated
            { new: true, upsert: false } // upsert: false ensures we only update existing users
        );

        if (!updatedUser) {
            return res.status(404).json({ success: false, message: "User not found" });
        }

        if (updateData.hasCompletedOnboarding === true) {
            analyticsService.trackEvent('onboarding_completed', phone);
        }

        res.json({ success: true, user: updatedUser });
    } catch (e) {
        console.error("UPDATE_PROFILE_ERROR:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.updatePremium = async (req, res) => {
    try {
        const { phone, isPremium } = req.body;
        const updatedUser = await User.findOneAndUpdate(
            { phone },
            { isPremium, lastSeen: new Date() },
            { new: true }
        );
        res.json({ success: true, user: updatedUser });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.getDiscover = async (req, res) => {
    try {
        const {
            phone,
            page = 1,
            limit = 10, // Requirement says load ONLY first 10
            tab = 'Nearby',
            distance,
            age,
            isOnlineOnly,
            havePlace,
            position,
            lat,
            lng
        } = req.query;

        let userLat = lat ? parseFloat(lat) : null;
        let userLng = lng ? parseFloat(lng) : null;

        // If lat/lng missing in query, try to get from user record
        if (!userLat || !userLng) {
            const caller = await User.findOne({ phone }, 'lat lng location');
            if (caller) {
                userLat = userLat || caller.lat || caller.location?.coordinates?.[1];
                userLng = userLng || caller.lng || caller.location?.coordinates?.[0];
            }
        }

        const pageNum = parseInt(page);
        const limitNum = parseInt(limit);
        const skip = (pageNum - 1) * limitNum;

        // Base query: exclude self, banned and deactivated users
        let baseQuery = {
            phone: { $ne: phone },
            isBanned: { $ne: true },
            isDeactivated: { $ne: true }
        };

        // Apply shared filters
        if (isOnlineOnly === 'true' || tab === 'Online') {
            baseQuery.isOnline = true;
        }

        if (havePlace && havePlace !== 'Any') {
            baseQuery.havePlace = havePlace;
        }

        if (position && position !== 'Any') {
            const searchTerms = position.split(',').map(p => p.trim()).filter(p => p.length > 0);
            baseQuery.$or = searchTerms.map(term => ({ position: { $regex: term, $options: 'i' } }));
        }

        if (age && age !== 'Any') {
            if (age === '18-25') baseQuery.age = { $gte: 18, $lte: 25 };
            else if (age === '26-35') baseQuery.age = { $gte: 26, $lte: 35 };
            else if (age === '36-45') baseQuery.age = { $gte: 36, $lte: 45 };
            else if (age === '46+') baseQuery.age = { $gte: 46 };
        }

        let sort = { lastSeen: -1 };
        let finalQuery = { ...baseQuery };

        // Handle tabs and geo-filtering
        if (tab === 'Nearby' && userLat && userLng) {
            // Determine search radiuses to try for smart expansion
            let radii = [20, 100, 500];

            if (distance && distance !== 'Any') {
                const requestedDist = parseInt(distance.replace('km', ''));
                if (!isNaN(requestedDist)) {
                    // Include user requested distance, then expand if needed
                    radii = [requestedDist, 20, 100, 500];
                    // Sort and filter to ensure we always try larger or equal to requested
                    radii = radii.filter(r => r >= requestedDist).sort((a, b) => a - b);
                    // Remove duplicates
                    radii = [...new Set(radii)];
                }
            }

            let users = [];
            let currentRadiusUsed = 0;

            // If it's page 1, we try expanding if empty to prevent "dead app" feeling
            if (pageNum === 1) {
                for (const radius of radii) {
                    currentRadiusUsed = radius;
                    const geoQuery = {
                        ...baseQuery,
                        location: {
                            $near: {
                                $geometry: { type: "Point", coordinates: [userLng, userLat] },
                                $maxDistance: radius * 1000 // meters
                            }
                        }
                    };

                    users = await User.find(geoQuery)
                        .limit(limitNum)
                        .select('phone name age position havePlace city area lat lng location isOnline isVerified isPremium profileImages')
                        .lean();

                    if (users.length > 0) break;
                }
            } else {
                // For subsequent pages, use the largest radius in our strategy
                // to ensure we can paginate through the expanded set.
                const searchRadius = radii[radii.length - 1];

                const geoQuery = {
                    ...baseQuery,
                    location: {
                        $near: {
                            $geometry: { type: "Point", coordinates: [userLng, searchRadius] },
                            $maxDistance: searchRadius * 1000
                        }
                    }
                };

                users = await User.find(geoQuery)
                    .skip(skip)
                    .limit(limitNum)
                    .select('phone name age position havePlace city area lat lng location isOnline isVerified isPremium profileImages')
                    .lean();
            }


            // Fallback: If still empty on page 1, show any active users regardless of distance
            if (users.length === 0 && pageNum === 1) {
                users = await User.find(baseQuery)
                    .sort({ lastSeen: -1 })
                    .limit(limitNum)
                    .select('phone name age position havePlace city area lat lng location isOnline isVerified isPremium profileImages')
                    .lean();
            }

            const processedUsers = (users || []).map(u => {
                const uLat = u.lat || u.location?.coordinates?.[1];
                const uLng = u.lng || u.location?.coordinates?.[0];
                const distanceStr = calculateDistance(userLat, userLng, uLat, uLng);

                // Best single location name (Village/Area > City)
                const cleanArea = (u.area && u.area.toLowerCase() !== 'unknown') ? u.area : '';
                const cleanCity = (u.city && u.city.toLowerCase() !== 'unknown') ? u.city : '';
                const cityLabel = cleanArea || cleanCity || 'Nearby';

                const { lat: _l, lng: _g, location: _loc, ...rest } = u;
                return { ...rest, city: cityLabel, area: '', distance: distanceStr };
            });

            return res.json({
                success: true,
                page: pageNum,
                users: processedUsers,
                radiusUsed: pageNum === 1 ? currentRadiusUsed : null
            });

        } else if (tab === 'New') {
            sort = { createdAt: -1 };
        } else if (tab === 'Popular') {
            sort = { isPremium: -1, lastSeen: -1 };
        } else if (tab === 'Online') {
            baseQuery.isOnline = true;
            sort = { lastSeen: -1 };
        }

        const users = await User.find(baseQuery)
            .sort(sort)
            .skip(skip)
            .limit(limitNum)
            .select('phone name age position havePlace city area lat lng location isOnline isVerified isPremium profileImages')
            .lean();

        const processedUsers = (users || []).map(u => {
            const uLat = u.lat || u.location?.coordinates?.[1];
            const uLng = u.lng || u.location?.coordinates?.[0];
            const distanceStr = calculateDistance(userLat, userLng, uLat, uLng);

            // Best single location name (Village/Area > City)
            const cleanArea = (u.area && u.area.toLowerCase() !== 'unknown') ? u.area : '';
            const cleanCity = (u.city && u.city.toLowerCase() !== 'unknown') ? u.city : '';
            const cityLabel = cleanArea || cleanCity || 'Nearby';

            const { lat: _l, lng: _g, location: _loc, ...rest } = u;
            return { ...rest, city: cityLabel, area: '', distance: distanceStr };
        });

        res.json({
            success: true,
            page: pageNum,
            users: processedUsers
        });

    } catch (e) {
        console.error("GET_DISCOVER_ERROR:", e);
        res.status(500).json({ success: false, users: [], error: e.message });
    }
};

exports.trackEvent = async (req, res) => {
    try {
        const { eventType, distinctId, metadata } = req.body;
        if (eventType) {
            analyticsService.trackEvent(eventType, distinctId, metadata);
        }
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.deactivateAccount = async (req, res) => {
    try {
        const { phone, reason } = req.body;
        const user = await User.findOne({ phone });
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        // Snapshot premium status
        const premiumSnapshot = {
            isPremium: user.isPremium,
            premiumExpiry: user.premiumExpiry,
            premiumPlan: user.premiumPlan,
            subscriptionStatus: user.subscription?.status
        };

        user.isDeactivated = true;
        user.accountStatus = 'Deactivated';
        user.deactivatedAt = new Date();
        user.deactivationReason = reason || 'User requested';
        user.lastPremiumSnapshot = premiumSnapshot;
        user.isOnline = false;

        await user.save();

        console.log(`[DEACTIVATION] User ${phone} deactivated.`);

        // Realtime notification
        const io = req.app.get('socketio');
        if (io) {
            io.emit('user_deactivated', { phone });
            // For active chats, we might want to emit to specific rooms,
            // but a global emit with phone is easier for clients to filter.
        }

        res.json({ success: true, message: 'Account deactivated successfully' });
    } catch (e) {
        console.error("DEACTIVATE_ACCOUNT_ERROR:", e);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

exports.reactivateAccount = async (req, res) => {
    try {
        const { phone } = req.body;
        const user = await User.findOne({ phone });
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });

        user.isDeactivated = false;
        user.accountStatus = 'Active';
        user.reactivatedAt = new Date();
        user.isOnline = true;

        await user.save();

        console.log(`[REACTIVATION] User ${phone} reactivated via manual request.`);

        // Realtime notification
        const io = req.app.get('socketio');
        if (io) {
            io.emit('user_reactivated', { phone });
        }

        res.json({ success: true, user });
    } catch (e) {
        console.error("REACTIVATE_ACCOUNT_ERROR:", e);
        res.status(500).json({ success: false, message: 'Server error' });
    }
};

