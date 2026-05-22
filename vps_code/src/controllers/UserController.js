const User = require('../models/User');
const Report = require('../models/Report');
const VerificationRequest = require('../models/VerificationRequest');

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
        const user = await User.findOne({ phone: req.params.phone });
        if (!user) return res.status(404).json({ success: false, message: 'User not found' });
        res.json({ success: true, user });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.login = async (req, res) => {
    try {
        const user = await User.findOne({ phone: req.body.phone });
        if (user) {
            if (user.isBanned) return res.status(403).json({ success: false, message: "Account banned: " + user.banReason });
            user.lastSeen = new Date();
            user.isOnline = true;
            await user.save();
            res.json({ success: true, user });
        } else {
            res.json({ success: false });
        }
    } catch (e) {
        res.status(500).json({ success: false });
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
    try {
        const newUser = new User(req.body);
        const savedUser = await newUser.save();
        res.json({ success: true, user: savedUser });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.updateLocation = async (req, res) => {
    try {
        const { phone, lat, lng, city, area } = req.body;
        const update = { lat, lng, city, area, lastSeen: new Date() };

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
            limit = 20,
            tab = 'Nearby',
            distance,
            age,
            isOnlineOnly,
            havePlace,
            position,
            lat,
            lng
        } = req.query;

        const skip = (parseInt(page) - 1) * parseInt(limit);

        // Basic query: Don't show self and don't show explicitly banned users
        const query = {
            phone: { $ne: phone },
            isBanned: { $ne: true }
        };

        // Filters - Only apply if they are not 'Any'
        if (isOnlineOnly === 'true') query.isOnline = true;
        if (havePlace && havePlace !== 'Any') query.havePlace = havePlace;

        if (position && position !== 'Any') {
            // If "Top, Ver" is passed, we check for both.
            // If any other specific position is passed, we check that.
            // We also handle cases where position might be empty in DB.
            const searchTerms = position.split(',').map(p => p.trim()).filter(p => p.length > 0);
            query.$or = searchTerms.map(term => ({ position: { $regex: term, $options: 'i' } }));
        }

        if (age && age !== 'Any') {
            if (age === '18-25') query.age = { $gte: 18, $lte: 25 };
            else if (age === '26-35') query.age = { $gte: 26, $lte: 35 };
            else if (age === '36-45') query.age = { $gte: 36, $lte: 45 };
            else if (age === '46+') query.age = { $gte: 46 };
        }

        let sort = { lastSeen: -1 };
        if (tab === 'Nearby') {
            sort = { lastSeen: -1 };
            // If distance filter is applied on Nearby tab using GeoJSON
            if (lat && lng && distance && distance !== 'Any') {
                const maxDistKm = parseInt(distance.replace('km', ''));
                if (!isNaN(maxDistKm)) {
                    query.location = {
                        $near: {
                            $geometry: { type: "Point", coordinates: [parseFloat(lng), parseFloat(lat)] },
                            $maxDistance: maxDistKm * 1000 // meters
                        }
                    };
                    // When using $near, sort is automatically by distance.
                    // If we want both, we might need $geoNear in aggregation, but $near is usually enough.
                    sort = {};
                }
            }
        } else if (tab === 'New') {
            sort = { createdAt: -1 };
        } else if (tab === 'Popular') {
            sort = { isPremium: -1, lastSeen: -1 };
        } else if (tab === 'Online') {
            query.isOnline = true;
            sort = { lastSeen: -1 };
        }

        const users = await User.find(query)
            .sort(sort)
            .skip(skip)
            .limit(parseInt(limit))
            .select('phone name age position havePlace city area lat lng isOnline isVerified isPremium profileImages')
            .lean();

        // Fallback: If no users found with strict filters on page 1, return active users
        if (users.length === 0 && parseInt(page) === 1) {
            const fallbackUsers = await User.find({ phone: { $ne: phone }, isBanned: { $ne: true } })
                .sort({ lastSeen: -1 })
                .limit(parseInt(limit))
                .select('phone name age position havePlace city area lat lng isOnline isVerified isPremium profileImages')
                .lean();
            return res.json({ success: true, page: 1, users: fallbackUsers || [] });
        }

        res.json({
            success: true,
            page: parseInt(page),
            users: users || []
        });
    } catch (e) {
        console.error("GET_DISCOVER_ERROR:", e);
        res.status(500).json({ success: false, users: [] });
    }
};
