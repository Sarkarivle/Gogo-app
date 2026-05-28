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
const path = require('path');
const fs = require('fs');

const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

const { normalize, phoneQuery } = require('../utils/phoneUtils');

// Helper for Audit Logging
const logAction = async (req, action, target, details) => {
    try {
        await new AdminLog({
            adminId: req.admin?.id,
            adminName: req.admin?.username,
            action,
            target,
            details,
            timestamp: new Date()
        }).save();
    } catch (e) { console.error("Audit Log Error:", e); }
};

exports.loginAdmin = async (req, res) => {
    try {
        const { username, password } = req.body;
        const admin = await Admin.findOne({ username });
        if (!admin || !(await bcrypt.compare(password, admin.password))) return res.status(401).json({ success: false });
        const token = jwt.sign({ id: admin._id, username: admin.username, role: admin.role }, JWT_SECRET, { expiresIn: '24h' });
        admin.lastLogin = new Date(); await admin.save();
        res.json({ success: true, token, admin: { username: admin.username, role: admin.role } });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.createAdmin = async (req, res) => {
    try {
        const INIT_SECRET = process.env.ADMIN_INIT_SECRET || 'GOGO_INIT_SECRET_99';
        if (req.body.secret !== INIT_SECRET) return res.status(403).json({ success: false });

        const { username, password, role } = req.body;
        const hashedPassword = await bcrypt.hash(password, 10);

        await new Admin({ username, password: hashedPassword, role: role || 'admin' }).save();
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getChatHistory = async (req, res) => {
    try {
        const p1 = normalize(req.params.p1), p2 = normalize(req.params.p2);
        const roomId = [p1, p2].sort().join('_');
        const chats = await Message.find({
            $or: [
                { roomId: roomId },
                { roomId: { $in: [`${p1}_${p2}`, `${p2}_${p1}`, `+91${p1}_${p2}`, `+91${p2}_${p1}`] } }
            ],
            deletedBy: { $ne: p1 }
        }).sort({ timestamp: -1 }).skip((parseInt(req.query.page || 1) - 1) * parseInt(req.query.limit || 50)).limit(parseInt(req.query.limit || 50));
        res.json(chats.reverse());
    } catch (e) { res.status(500).json([]); }
};

exports.getStats = async (req, res) => {
    console.log(`📊 [${new Date().toISOString()}] Admin API: getStats requested by ${req.admin?.username}`);
    try {
        const stats = await analyticsService.getDashboardStats();
        res.json({ success: true, stats });
    } catch (e) {
        console.error("❌ Dashboard Stats Error:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.getAnalytics = async (req, res) => {
    try { res.json(await analyticsService.getDashboardStats()); } catch (e) { res.status(500).json({}); }
};

exports.getAdmins = async (req, res) => {
    try { res.json(await Admin.find({}, 'username role')); } catch (e) { res.status(500).json([]); }
};

exports.getAllUsers = async (req, res) => {
    try {
        const q = req.query.search ? { $or: [{ phone: { $regex: req.query.search, $options: 'i' } }, { name: { $regex: req.query.search, $options: 'i' } }] } : {};
        res.json(await User.find(q).sort({ createdAt: -1 }).limit(100));
    } catch (e) { res.status(500).json([]); }
};

exports.getUserFullProfile = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const pQ = phoneQuery(phone);
        const [user, reports, blocks, sub, payments] = await Promise.all([
            User.findOne(pQ),
            Report.find({ reportedPhone: new RegExp(phone + '$') }).sort({ timestamp: -1 }),
            Block.find({ blockedPhone: new RegExp(phone + '$') }).sort({ timestamp: -1 }),
            Subscription.findOne({ userPhone: new RegExp(phone + '$') }),
            revenueService.getPaymentHistory({ userPhone: new RegExp(phone + '$') }, 1, 50)
        ]);
        if (!user) return res.status(404).json({ success: false });
        res.json({ success: true, user, reportsAgainst: reports, blockedBy: blocks, subscription: sub || { status: 'None' }, paymentHistory: payments.history || [] });
    } catch (error) { res.status(500).json({ success: false }); }
};

exports.updateUserStatus = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        // Security: Whitelist allowed fields to prevent accidental or malicious escalation
        const allowedUpdates = [
            'accountStatus', 'isBanned', 'isPremium', 'premiumExpiry',
            'isVerified', 'isDeactivated', 'name', 'bio', 'gender'
        ];

        const filteredUpdate = {};
        allowedUpdates.forEach(key => {
            if (req.body[key] !== undefined) filteredUpdate[key] = req.body[key];
        });

        const user = await User.findOneAndUpdate(phoneQuery(phone), filteredUpdate, { new: true });
        if (!user) return res.status(404).json({ success: false });

        await logAction(req, "Update User Status", phone, JSON.stringify(filteredUpdate));

        const io = req.app.get('socketio');
        if (io) {
            io.to(`user_${phone}`).emit('profile_sync_required', { type: 'STATUS_UPDATE', fullUser: user });
            if (user.accountStatus === 'Suspended' || user.accountStatus === 'Banned') io.to(`user_${phone}`).emit('force_action', { action: 'LOGOUT' });
        }
        res.json({ success: true, user });
    } catch (error) { res.status(500).json({ success: false }); }
};

exports.addAdminNote = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const user = await User.findOneAndUpdate(phoneQuery(phone), { $push: { adminNotes: { ...req.body, timestamp: new Date() } } }, { new: true });
        res.json({ success: true, user });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.sendDirectNotification = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const io = req.app.get('socketio');
        if (io) io.to(`user_${phone}`).emit('admin_alert', req.body);
        const user = await User.findOne(phoneQuery(phone), 'fcmToken');
        if (user?.fcmToken) await notificationService.sendPushNotification(user.fcmToken, req.body.title, req.body.message);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.clearUserChat = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const pQ = new RegExp(phone + '$');
        await Message.deleteMany({ $or: [{ senderPhone: pQ }, { receiverPhone: pQ }] });

        await logAction(req, "Clear Chat History", phone, "Wiped all message logs for user");

        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.deleteUser = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const pQ = new RegExp(phone + '$');
        await Promise.all([
            User.findOneAndDelete(phoneQuery(phone)),
            Message.deleteMany({ $or: [{ senderPhone: pQ }, { receiverPhone: pQ }] }),
            Report.deleteMany({ $or: [{ reporterPhone: pQ }, { reportedPhone: pQ }] }),
            Block.deleteMany({ $or: [{ blockerPhone: pQ }, { blockedPhone: pQ }] }),
            Subscription.findOneAndDelete({ userPhone: pQ })
        ]);

        await logAction(req, "Delete Account", phone, "Permanently wiped user data");

        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getReports = async (req, res) => {
    try { res.json(await Report.find().sort({ timestamp: -1 })); } catch (e) { res.status(500).json([]); }
};

exports.handleReport = async (req, res) => {
    try {
        const report = await Report.findById(req.body.reportId);
        if (req.body.action === 'ban') await User.findOneAndUpdate({ phone: report.reportedPhone }, { isBanned: true });
        report.status = 'Reviewed'; await report.save();
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getVerificationRequests = async (req, res) => {
    try { res.json(await VerificationRequest.find({ status: 'Pending' })); } catch (e) { res.status(500).json([]); }
};

exports.approveVerification = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        await Promise.all([
            User.findOneAndUpdate(phoneQuery(phone), { isVerified: true }),
            VerificationRequest.findOneAndUpdate({ userPhone: new RegExp(phone + '$') }, { status: 'Approved' })
        ]);

        await logAction(req, "Approve Identity", phone, "Manual ID verification approved");

        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.broadcastNotification = async (req, res) => {
    const { title, message } = req.body;
    console.log(`📣 [${new Date().toISOString()}] Broadcast triggered: "${title}" - "${message}"`);

    try {
        if (!message) return res.status(400).json({ success: false, message: "Message body is required" });

        const io = req.app.get('socketio');
        if (io) {
            io.emit('admin_alert', { title, message, timestamp: new Date() });
            console.log("📡 Socket broadcast emitted to all online users");
        }

        const users = await User.find({ fcmToken: { $exists: true, $ne: null } }, 'fcmToken phone');
        console.log(`👥 Found ${users.length} users with FCM tokens in database`);

        let successCount = 0;
        const sendPromises = users.map(async (u) => {
            if (u.fcmToken) {
                const success = await notificationService.sendPushNotification(
                    u.fcmToken,
                    title || "Broadcast",
                    message,
                    { type: 'broadcast' }
                );
                if (success) successCount++;
            }
        });

        await Promise.all(sendPromises);
        console.log(`✅ Broadcast finished. Successful deliveries: ${successCount}/${users.length}`);

        await logAction(req, "Global Broadcast", "All Users", message);

        res.json({ success: true, targetCount: users.length, deliveredCount: successCount });
    } catch (e) {
        console.error("❌ Broadcast Error:", e);
        res.status(500).json({ success: false, error: e.message });
    }
};

exports.getUserInboxes = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const pQ = new RegExp(phone + '$');
        const messages = await Message.find({ $or: [{ senderPhone: pQ }, { receiverPhone: pQ }] }).sort({ timestamp: -1 });
        let pMap = {};
        for (const m of messages) {
            let sP = normalize(m.senderPhone);
            let rP = normalize(m.receiverPhone);
            let other = sP === phone ? rP : sP;
            if (!pMap[other]) pMap[other] = { phone: other, lastMsg: m.message || 'Media', timestamp: m.timestamp };
        }
        res.json(Object.values(pMap));
    } catch (e) { res.status(500).json([]); }
};

exports.getMonitoringData = async (req, res) => {
    try {
        const data = await analyticsService.getLiveMonitoringData();
        res.json(data);
    } catch (e) {
        console.error("Monitoring Data Error:", e);
        res.status(500).json({ success: false, message: "Internal server error" });
    }
};

exports.getAuditLogs = async (req, res) => {
    try { res.json(await AdminLog.find().sort({ timestamp: -1 }).limit(100)); } catch (e) { res.status(500).json([]); }
};

exports.getFeatureFlags = async (req, res) => {
    try { res.json(await FeatureFlag.find()); } catch (e) { res.status(500).json([]); }
};

exports.toggleFeatureFlag = async (req, res) => {
    try {
        await FeatureFlag.findOneAndUpdate({ key: req.body.key }, { isEnabled: req.body.isEnabled, updatedAt: new Date() }, { upsert: true });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getConfig = async (req, res) => {
    try {
        const config = await Config.findOne({ key: req.params.key });
        res.json({ success: true, config: config ? config.value : {} });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.updateConfig = async (req, res) => {
    try {
        await Config.findOneAndUpdate({ key: req.body.key }, { value: req.body.value, updatedAt: new Date() }, { upsert: true });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getMonetizationStats = async (req, res) => {
    try {
        const stats = await revenueService.getFinancialMetrics();
        res.json({ success: true, stats });
    } catch (e) {
        console.error("Monetization Stats Error:", e);
        res.status(500).json({ success: false, error: e.message });
    }
};

exports.getPaymentHistory = async (req, res) => {
    try { res.json({ success: true, ...await revenueService.getPaymentHistory({}, parseInt(req.query.page || 1), parseInt(req.query.limit || 20)) }); } catch (e) { res.status(500).json({ success: false }); }
};

exports.getAllMedia = async (req, res) => {
    try {
        const [users, messages] = await Promise.all([
            User.find({ profileImages: { $exists: true, $not: { $size: 0 } } }, 'phone profileImages name'),
            Message.find({ type: 'image' }, 'senderPhone imageUrl timestamp').sort({ timestamp: -1 }).limit(100)
        ]);
        let allMedia = [];
        users.forEach(u => u.profileImages.forEach(img => allMedia.push({ url: img, owner: normalize(u.phone), ownerName: u.name, type: 'Profile', timestamp: u.updatedAt || new Date() })));
        messages.forEach(m => m.imageUrl && allMedia.push({ url: m.imageUrl, owner: normalize(m.senderPhone), type: 'Chat', timestamp: m.timestamp }));
        res.json({ success: true, media: allMedia.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp)) });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.deleteMedia = async (req, res) => {
    try {
        const fileName = req.body.url.split('/').pop().split('?')[0];
        // Security: Prevent path traversal
        if (fileName.includes('..') || fileName.includes('/') || fileName.includes('\\')) {
            return res.status(400).json({ success: false, message: "Invalid filename" });
        }

        const filePath = path.join(__dirname, '../../uploads', fileName);

        // Use fs.promises for non-blocking I/O
        if (fs.existsSync(filePath)) {
            await fs.promises.unlink(filePath).catch(err => console.error("File Delete Error:", err));
        }

        if (req.body.type === 'Profile') await User.findOneAndUpdate(phoneQuery(req.body.owner), { $pull: { profileImages: req.body.url.split('?')[0] } });
        else if (req.body.type === 'Chat') await Message.findOneAndUpdate({ imageUrl: req.body.url.split('?')[0] }, { $set: { message: "[Deleted]", imageUrl: null, type: 'text' } });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};
