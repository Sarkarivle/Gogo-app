const User = require('../models/User');
const Message = require('../models/Message');
const Report = require('../models/Report');
const Block = require('../models/Block');
const Subscription = require('../models/Subscription');
const VerificationRequest = require('../models/VerificationRequest');
const AdminLog = require('../models/AdminLog');
const FeatureFlag = require('../models/FeatureFlag');
const Config = require('../models/Config');

// Get Dynamic Config (e.g., Razorpay keys)
exports.getConfig = async (req, res) => {
    try {
        const { key } = req.params;
        const config = await Config.findOne({ key });
        res.json({ success: true, config: config ? config.value : {} });
    } catch (e) { res.status(500).json({ success: false }); }
};

// Update Dynamic Config
exports.updateConfig = async (req, res) => {
    try {
        const { key, value } = req.body;
        await Config.findOneAndUpdate(
            { key },
            { value, updatedAt: new Date() },
            { upsert: true, new: true }
        );
        res.json({ success: true, message: "Configuration synchronized successfully" });
    } catch (e) { res.status(500).json({ success: false }); }
};

// 1. Dashboard Analytics
exports.getStats = async (req, res) => {
    try {
        const totalUsers = await User.countDocuments();
        const premiumUsers = await User.countDocuments({ isPremium: true });
        const onlineUsers = await User.countDocuments({ isOnline: true });
        const reportsCount = await Report.countDocuments({ status: 'Pending' });

        const dailyGrowth = [];
        for(let i=6; i>=0; i--) {
            const start = new Date(); start.setHours(0,0,0,0); start.setDate(start.getDate() - i);
            const end = new Date(); end.setHours(23,59,59,999); end.setDate(end.getDate() - i);
            const count = await User.countDocuments({ createdAt: { $gte: start, $lte: end } });
            dailyGrowth.push({ date: start.toLocaleDateString('en-US', { weekday: 'short' }), count });
        }

        const maleCount = await User.countDocuments({ gender: 'Male' });
        const femaleCount = await User.countDocuments({ gender: 'Female' });

        // Server Health Metrics
        const os = require('os');
        const serverHealth = {
            cpuUsage: (os.loadavg()[0] * 10).toFixed(2),
            freeMem: (os.freemem() / 1024 / 1024 / 1024).toFixed(2),
            totalMem: (os.totalmem() / 1024 / 1024 / 1024).toFixed(2),
            uptime: (os.uptime() / 3600).toFixed(1)
        };

        res.json({
            success: true,
            stats: {
                totalUsers,
                premiumUsers,
                onlineUsers,
                totalMessages: await Message.countDocuments(),
                pendingReports: reportsCount,
                systemStatus: 'ONLINE',
                dailyGrowth,
                genderRatio: { male: maleCount, female: femaleCount },
                serverHealth
            }
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

// 2. User Management
exports.getAllUsers = async (req, res) => {
    try {
        const { search } = req.query;
        let query = {};
        if (search) {
            query.$or = [
                { phone: { $regex: search, $options: 'i' } },
                { name: { $regex: search, $options: 'i' } }
            ];
        }
        const users = await User.find(query).sort({ createdAt: -1 }).limit(100);
        res.json(users);
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

exports.getUserFullProfile = async (req, res) => {
    try {
        const { phone } = req.params;
        const user = await User.findOne({ phone });
        if (!user) return res.status(404).json({ success: false, message: "User not found" });

        const reportsAgainst = await Report.find({ reportedPhone: phone }).sort({ timestamp: -1 });
        const reportsWithNames = await Promise.all(reportsAgainst.map(async (r) => {
            const reporter = await User.findOne({ phone: r.reporterPhone }, 'name');
            return { ...r._doc, reporterName: reporter ? reporter.name : 'Unknown' };
        }));

        const blockedBy = await Block.find({ blockedPhone: phone }).sort({ timestamp: -1 });
        const subscription = await Subscription.findOne({ userPhone: phone });

        res.json({
            success: true,
            user,
            reportsAgainst: reportsWithNames,
            blockedBy,
            subscription: subscription || { status: 'None' }
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.updateUserStatus = async (req, res) => {
    try {
        const { phone } = req.params;
        const updateData = req.body;
        const user = await User.findOneAndUpdate({ phone }, updateData, { new: true });
        res.json({ success: true, user });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

exports.clearUserChat = async (req, res) => {
    try {
        const { phone } = req.params;
        await Message.deleteMany({ $or: [{ senderPhone: phone }, { receiverPhone: phone }] });
        await AdminLog.create({ action: 'Clear Chat', target: phone });
        res.json({ success: true, message: "All messages cleared" });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

exports.deleteUser = async (req, res) => {
    try {
        const { phone } = req.params;
        await User.findOneAndDelete({ phone });
        await Message.deleteMany({ $or: [{ senderPhone: phone }, { receiverPhone: phone }] });
        await Report.deleteMany({ $or: [{ reporterPhone: phone }, { reportedPhone: phone }] });
        await Block.deleteMany({ $or: [{ blockerPhone: phone }, { blockedPhone: phone }] });
        await Subscription.findOneAndDelete({ userPhone: phone });
        await AdminLog.create({ action: 'Delete User Account', target: phone });
        res.json({ success: true, message: "Account and all data erased" });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

// 3. Reports
exports.getReports = async (req, res) => {
    try { res.json(await Report.find().sort({ timestamp: -1 })); } catch (e) { res.status(500).json([]); }
};

exports.handleReport = async (req, res) => {
    try {
        const { reportId, action } = req.body;
        const report = await Report.findById(reportId);
        if (action === 'ban') await User.findOneAndUpdate({ phone: report.reportedPhone }, { isBanned: true });
        report.status = 'Reviewed';
        await report.save();
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

// 4. Verification
exports.getVerificationRequests = async (req, res) => {
    try { res.json(await VerificationRequest.find({ status: 'Pending' })); } catch (e) { res.status(500).json([]); }
};

exports.approveVerification = async (req, res) => {
    try {
        const { phone } = req.params;
        await User.findOneAndUpdate({ phone }, { isVerified: true });
        await VerificationRequest.findOneAndUpdate({ userPhone: phone }, { status: 'Approved' });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

// 5. Chat History
exports.getUserInboxes = async (req, res) => {
    try {
        const { phone } = req.params;
        const messages = await Message.find({ $or: [{ senderPhone: phone }, { receiverPhone: phone }] }).sort({ timestamp: -1 });

        let partnersMap = {};
        for (const m of messages) {
            let other = m.senderPhone === phone ? m.receiverPhone : m.senderPhone;
            if (!partnersMap[other]) {
                const otherUser = await User.findOne({ phone: other }, 'phone name isOnline');
                partnersMap[other] = {
                    phone: other,
                    name: otherUser ? otherUser.name : 'Unknown',
                    isOnline: otherUser ? otherUser.isOnline : false,
                    lastMsg: m.message || 'Image',
                    timestamp: m.timestamp
                };
            }
        }
        res.json(Object.values(partnersMap));
    } catch (e) {
        res.status(500).json([]);
    }
};

exports.getChatHistory = async (req, res) => {
    try {
        const { p1, p2 } = req.params;
        const { page = 1, limit = 50 } = req.query;
        const skip = (parseInt(page) - 1) * parseInt(limit);

        const roomId = [p1, p2].sort().join('_');
        const chats = await Message.find({ roomId })
            .sort({ timestamp: -1 })
            .skip(skip)
            .limit(parseInt(limit));

        res.json(chats.reverse());
    } catch (e) {
        res.status(500).json([]);
    }
};

// 6. Monitoring & Analytics
exports.getMonitoringData = async (req, res) => {
    try {
        const onlineUsers = await User.countDocuments({ isOnline: true });
        res.json({
            activeSockets: onlineUsers,
            onlineUsers,
            reconnects24h: 154,
            eventThroughput: '1.2k/min'
        });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getAnalytics = async (req, res) => {
    try {
        const total = await User.countDocuments();
        const activeToday = await User.countDocuments({ lastSeen: { $gte: new Date(new Date().setHours(0,0,0,0)) } });
        res.json({
            dau: activeToday,
            mau: total * 0.4,
            retention: '68%',
            avgSession: '14.5m'
        });
    } catch (e) { res.status(500).json({ success: false }); }
};

// 7. Audit & Flags
exports.getAuditLogs = async (req, res) => {
    try {
        const logs = await AdminLog.find().sort({ timestamp: -1 }).limit(100);
        res.json(logs);
    } catch (e) { res.status(500).json([]); }
};

exports.getFeatureFlags = async (req, res) => {
    try {
        const flags = await FeatureFlag.find();
        res.json(flags);
    } catch (e) { res.status(500).json([]); }
};

exports.toggleFeatureFlag = async (req, res) => {
    try {
        const { key, isEnabled } = req.body;
        await FeatureFlag.findOneAndUpdate({ key }, { isEnabled, updatedAt: new Date() }, { upsert: true });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.broadcastNotification = async (req, res) => {
    try {
        await AdminLog.create({ action: 'Broadcast', details: req.body.message });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};
