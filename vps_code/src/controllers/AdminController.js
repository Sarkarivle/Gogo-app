const User = require('../models/User');
const Admin = require('../models/Admin');
const Message = require('../models/Message');
const Report = require('../models/Report');
const Block = require('../models/Block');
const Subscription = require('../models/Subscription');
const VerificationRequest = require('../models/VerificationRequest');
const AdminLog = require('../models/AdminLog');
const FeatureFlag = require('../models/FeatureFlag');
const Config = require('../models/Config');
const analyticsService = require('../services/analyticsService');
const revenueService = require('../services/revenueService');
const notificationService = require('../services/notificationService');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');

const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

// Admin Login
exports.loginAdmin = async (req, res) => {
    try {
        const { username, password } = req.body;
        console.log(`🔐 Admin login attempt: ${username}`);

        const admin = await Admin.findOne({ username });
        if (!admin) {
            return res.status(401).json({ success: false, message: "Invalid credentials" });
        }

        const isMatch = await bcrypt.compare(password, admin.password);
        if (!isMatch) {
            return res.status(401).json({ success: false, message: "Invalid credentials" });
        }

        // Generate JWT Token
        const token = jwt.sign(
            { id: admin._id, username: admin.username, role: admin.role },
            JWT_SECRET,
            { expiresIn: '24h' }
        );

        admin.lastLogin = new Date();
        await admin.save();

        await AdminLog.create({ action: 'Login', details: `Admin ${username} logged in` });

        res.json({
            success: true,
            token,
            admin: {
                username: admin.username,
                role: admin.role
            }
        });
    } catch (e) {
        console.error("LOGIN_ERROR:", e);
        res.status(500).json({ success: false, message: "Server error" });
    }
};

// Create Initial Admin (Use this once or protect it)
exports.createAdmin = async (req, res) => {
    try {
        const { username, password, role, secret } = req.body;
        // Simple safety check for initial creation
        if (secret !== 'GOGO_INIT_SECRET_99') return res.status(403).json({ success: false });

        const admin = new Admin({ username, password, role });
        await admin.save();
        res.json({ success: true, message: "Admin created" });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};

// Get Dynamic Config (e.g., Razorpay keys)
exports.getConfig = async (req, res) => {
    try {
        const { key } = req.params;
        const config = await Config.findOne({ key });
        console.log(`🔍 Fetching config for key: ${key}`, config ? config.value : 'Not found');
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

        // --- REALTIME NOTIFICATION FOR APP UPDATE ---
        if (key === 'app_update_config') {
            const io = req.app.get('socketio');
            if (io) {
                console.log("📢 Emitting app_config_sync to all users");
                io.emit('app_config_sync', { key: 'app_update_config' });
            }
        }

        res.json({ success: true, message: "Configuration synchronized successfully" });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getAdmins = async (req, res) => {
    try {
        const admins = await require('../models/Admin').find({}, 'username role');
        res.json(admins);
    } catch (e) { res.status(500).json([]); }
};

// 1. Dashboard Analytics
exports.getStats = async (req, res) => {
    try {
        const stats = await analyticsService.getDashboardStats();

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
                ...stats,
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

        // Fetch detailed payment history for this specific user
        const payments = await revenueService.getPaymentHistory({ userPhone: phone }, 1, 50);

        res.json({
            success: true,
            user,
            reportsAgainst: reportsWithNames,
            blockedBy,
            subscription: subscription || { status: 'None' },
            paymentHistory: payments.history || []
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

        // --- REALTIME SYNC TO APP ---
        const io = req.app.get('socketio');
        if (io) {
            // Emit to the specific user's personal room
            io.to(`user_${phone}`).emit('profile_sync_required', {
                type: 'STATUS_UPDATE',
                isPremium: user.isPremium,
                isVerified: user.isVerified,
                accountStatus: user.accountStatus,
                isShadowBanned: user.isShadowBanned,
                fullUser: user // Send full object for complete sync
            });

            // If account is suspended or banned, force logout or block UI
            if (user.accountStatus === 'Suspended' || user.accountStatus === 'Banned') {
                io.to(`user_${phone}`).emit('force_action', { action: 'LOGOUT', reason: 'Account suspended by moderator' });
            }
        }

        res.json({ success: true, user });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

exports.addAdminNote = async (req, res) => {
    try {
        const { phone } = req.params;
        const { note, adminName } = req.body;
        const user = await User.findOneAndUpdate(
            { phone },
            { $push: { adminNotes: { note, adminName, timestamp: new Date() } } },
            { new: true }
        );
        res.json({ success: true, user });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.sendDirectNotification = async (req, res) => {
    try {
        const { phone } = req.params;
        const { title, message } = req.body;

        // --- REALTIME SOCKET EMIT (Immediate Action) ---
        const io = req.app.get('socketio');
        if (io) {
            io.to(`user_${phone}`).emit('admin_alert', { title, message });
        }

        // Fallback to FCM for background delivery
        const user = await User.findOne({ phone }, 'fcmToken');
        if (user && user.fcmToken) {
            await notificationService.sendPushNotification(user.fcmToken, title, message, { type: 'admin_direct' });
            await AdminLog.create({ action: 'Direct Notification', target: phone, details: `Title: ${title}, Msg: ${message}` });
        }

        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
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
        const stats = await analyticsService.getDashboardStats();
        res.json({
            activeSockets: analyticsService.io ? analyticsService.io.engine.clientsCount : 0,
            onlineUsers: stats.onlineUsers,
            reconnects24h: analyticsService.metrics.reconnects24h,
            eventThroughput: `${(analyticsService.metrics.eventThroughput / 60).toFixed(1)}/sec`
        });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getAnalytics = async (req, res) => {
    try {
        const stats = await analyticsService.getDashboardStats();
        res.json(stats);
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
        const { title, message } = req.body;

        // 1. Log the broadcast
        await AdminLog.create({ action: 'Broadcast', details: `Title: ${title}, Msg: ${message}` });

        // 2. Real-time Socket Broadcast (Immediate)
        const io = req.app.get('socketio');
        if (io) {
            console.log("📢 Broadcasting admin_alert to all connected sockets");
            io.emit('admin_alert', { title, message });
        }

        // 3. Push Notification to all registered users with FCM tokens
        const users = await User.find({ fcmToken: { $exists: true, $ne: null } }, 'fcmToken');
        const tokens = users.map(u => u.fcmToken);

        if (tokens.length > 0) {
            console.log(`🚀 Sending Push Broadcast to ${tokens.length} devices`);
            // We use a loop for now. For massive scale, we should use admin.messaging().sendEachForMulticast()
            for (const token of tokens) {
                notificationService.sendPushNotification(token, title || "Announcement", message, { type: 'broadcast' });
            }
        }

        res.json({ success: true, message: `Broadcast sent to ${tokens.length} devices` });
    } catch (e) {
        console.error("BROADCAST_ERROR:", e);
        res.status(500).json({ success: false, error: e.message });
    }
};

// 8. Monetization
exports.getMonetizationStats = async (req, res) => {
    try {
        const stats = await revenueService.getFinancialMetrics();
        res.json({ success: true, stats });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getPaymentHistory = async (req, res) => {
    try {
        const { page = 1, limit = 20, search } = req.query;
        let query = {};
        if (search) {
            query.$or = [
                { userPhone: { $regex: search, $options: 'i' } },
                { orderId: { $regex: search, $options: 'i' } }
            ];
        }
        const history = await revenueService.getPaymentHistory(query, parseInt(page), parseInt(limit));
        res.json({ success: true, ...history });
    } catch (e) { res.status(500).json({ success: false }); }
};

// 9. Media Management & Moderation
exports.getAllMedia = async (req, res) => {
    try {
        const { filter = 'all', reportedOnly = 'false' } = req.query;
        const MASTER_SECRET = 'GOGO_SECURE_ACCESS_2024_PROD';

        let reportedPhones = [];
        if (reportedOnly === 'true') {
            const reports = await Report.find({ status: 'Pending' }, 'reportedPhone');
            reportedPhones = reports.map(r => r.reportedPhone);
        }

        const userQuery = {};
        if (reportedOnly === 'true') userQuery.phone = { $in: reportedPhones };
        if (filter === 'Chat') userQuery.phone = { $in: [] }; // Don't fetch users if chat only

        const msgQuery = { type: 'image' };
        if (reportedOnly === 'true') {
            msgQuery.$or = [
                { senderPhone: { $in: reportedPhones } },
                { receiverPhone: { $in: reportedPhones } }
            ];
        }
        if (filter === 'Profile') msgQuery.type = 'none'; // Don't fetch msgs if profile only

        const [users, messages] = await Promise.all([
            filter !== 'Chat' ? User.find({ ...userQuery, profileImages: { $exists: true, $not: { $size: 0 } } }, 'phone profileImages name') : [],
            filter !== 'Profile' ? Message.find(msgQuery, 'senderPhone imageUrl timestamp').sort({ timestamp: -1 }).limit(100) : []
        ]);

        let allMedia = [];
        users.forEach(u => {
            u.profileImages.forEach(img => {
                allMedia.push({
                    url: `${img}?token=${MASTER_SECRET}`,
                    owner: u.phone,
                    ownerName: u.name,
                    type: 'Profile',
                    timestamp: u.updatedAt || new Date()
                });
            });
        });

        messages.forEach(m => {
            if (m.imageUrl) {
                allMedia.push({
                    url: `${m.imageUrl}?token=${MASTER_SECRET}`,
                    owner: m.senderPhone,
                    type: 'Chat',
                    timestamp: m.timestamp
                });
            }
        });

        allMedia.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
        res.json({ success: true, media: allMedia });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.deleteMedia = async (req, res) => {
    try {
        const { url, type, owner } = req.body;
        const fs = require('fs');
        const path = require('path');

        // 1. Delete from File System
        try {
            const fileName = url.split('/').pop();
            const filePath = path.join(__dirname, '../../uploads', fileName);
            if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
        } catch (fErr) { console.error("File delete error:", fErr); }

        // 2. Remove from Database
        if (type === 'Profile') {
            await User.findOneAndUpdate({ phone: owner }, { $pull: { profileImages: url } });
        } else if (type === 'Chat') {
            await Message.findOneAndUpdate({ imageUrl: url }, { $set: { message: "[Deleted by Admin]", imageUrl: null, type: 'text' } });
        }

        await AdminLog.create({ action: 'Delete Media', target: owner, details: `Deleted ${type} image: ${url}` });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};
