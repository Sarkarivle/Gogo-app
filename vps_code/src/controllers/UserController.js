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
        await User.findOneAndUpdate({ phone }, { lat, lng, city, area, lastSeen: new Date() });
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.updateProfile = async (req, res) => {
    try {
        const { phone, ...updateData } = req.body;
        updateData.lastSeen = new Date();
        const updatedUser = await User.findOneAndUpdate({ phone }, updateData, { new: true });
        res.json({ success: true, user: updatedUser });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.updatePremium = async (req, res) => {
    try {
        const { phone, isPremium } = req.body;
        const updatedUser = await User.findOneAndUpdate(
            { phone },
            { isPremium, hasCompletedOnboarding: true, lastSeen: new Date() },
            { new: true }
        );
        res.json({ success: true, user: updatedUser });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};
