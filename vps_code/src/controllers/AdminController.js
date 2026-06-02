const User = require('../models/User');
const Admin = require('../models/Admin');
const Message = require('../models/Message');
const Report = require('../models/Report');
const Block = require('../models/Block');
const Subscription = require('../models/Subscription');
const VerificationRequest = require('../models/VerificationRequest');
const AdminLog = require('../models/AdminLog');
const FeatureFlag = require('../models/FeatureFlag');
const AnalyticsEvent = require('../models/AnalyticsEvent');
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
        const { search, status, accountStatus, dateRange, sortBy, sortOrder } = req.query;
        console.log(`👥 [${new Date().toISOString()}] Admin API: getAllUsers requested. Filters:`, req.query);

        let q = {};

        if (search) {
            q.$or = [
                { phone: { $regex: search, $options: 'i' } },
                { name: { $regex: search, $options: 'i' } }
            ];
        }

        if (status === 'online') {
            q.isOnline = true;
        } else if (status === 'offline') {
            q.isOnline = false;
        }

        if (accountStatus && accountStatus !== 'All') {
            q.accountStatus = accountStatus;
        }

        if (dateRange && dateRange !== 'all') {
            const now = new Date();
            let startDate = new Date();
            let endDate = new Date();

            if (dateRange === 'today') {
                startDate.setHours(0, 0, 0, 0);
                q.createdAt = { $gte: startDate };
            } else if (dateRange === 'yesterday') {
                startDate.setDate(now.getDate() - 1);
                startDate.setHours(0, 0, 0, 0);
                endDate.setDate(now.getDate() - 1);
                endDate.setHours(23, 59, 59, 999);
                q.createdAt = { $gte: startDate, $lte: endDate };
            } else if (dateRange === 'last7days') {
                startDate.setDate(now.getDate() - 7);
                startDate.setHours(0, 0, 0, 0);
                q.createdAt = { $gte: startDate };
            }
        }

        // Sorting Logic
        let sort = { createdAt: -1 };
        if (sortBy) {
            sort = { [sortBy]: sortOrder === 'asc' ? 1 : -1 };
        }

        const usersRaw = await User.find(q)
            .select('name phone city isOnline isPremium isVerified isShadowBanned accountStatus isDeactivated deviceHistory createdAt')
            .sort(sort)
            .limit(100)
            .lean()
            .maxTimeMS(5000);

        // Calculate Trust Score for each user
        const users = usersRaw.map(u => {
            let score = 70;
            if (u.isVerified) score += 15;
            if (u.isPremium) score += 10;
            if (u.isShadowBanned) score -= 30;
            if (u.accountStatus === 'Suspended' || u.accountStatus === 'Banned') score = 0;
            if (u.deviceHistory && u.deviceHistory.length > 2) score -= (u.deviceHistory.length * 3);

            const finalScore = Math.max(0, Math.min(100, score));
            return { ...u, trustScore: finalScore };
        });

        // Apply Trust Score Filtering if requested
        let filteredUsers = users;
        if (req.query.trustLevel) {
            if (req.query.trustLevel === 'high') filteredUsers = users.filter(u => u.trustScore >= 80);
            else if (req.query.trustLevel === 'medium') filteredUsers = users.filter(u => u.trustScore >= 40 && u.trustScore < 80);
            else if (req.query.trustLevel === 'low') filteredUsers = users.filter(u => u.trustScore < 40);
        }

        // Fetch Analytics for User Header
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);

        const [totalUsers, onlineUsers, todayJoined] = await Promise.all([
            User.countDocuments(),
            User.countDocuments({ isOnline: true }),
            User.countDocuments({ createdAt: { $gte: todayStart } })
        ]);

        console.log(`✅ Found ${filteredUsers.length} users with filters and sort`);
        res.json({
            users: filteredUsers,
            stats: {
                totalUsers,
                onlineUsers,
                todayJoined
            }
        });
    } catch (e) {
        console.error("❌ Admin GetAllUsers Error:", e);
        try {
            const fallbackUsers = await User.find({}).select('name phone').limit(20).lean();
            res.json(fallbackUsers);
        } catch (err2) {
            res.status(500).json([]);
        }
    }
};

exports.getUserFullProfile = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const pQ = phoneQuery(phone);
        const [user, reports, blocksRaw, sub, payments] = await Promise.all([
            User.findOne(pQ),
            Report.find({ reportedPhone: new RegExp(phone + '$') }).sort({ timestamp: -1 }),
            Block.find({ blockedPhone: new RegExp(phone + '$') }).sort({ timestamp: -1 }),
            Subscription.findOne({ userPhone: new RegExp(phone + '$') }),
            revenueService.getPaymentHistory({ userPhone: new RegExp(phone + '$') }, 1, 50)
        ]);

        if (!user) return res.status(404).json({ success: false });

        // Enrich block data with names
        const blockerPhones = blocksRaw.map(b => b.blockerPhone);
        const blockers = await User.find({
            phone: { $in: blockerPhones.map(p => new RegExp(p + '$')) }
        }).select('phone name');

        const blocks = blocksRaw.map(b => {
            const blocker = blockers.find(u => normalize(u.phone) === normalize(b.blockerPhone));
            return {
                ...b.toObject(),
                blockerName: blocker ? blocker.name : 'Unknown'
            };
        });

        res.json({
            success: true,
            user,
            reportsAgainst: reports,
            blockedBy: blocks,
            subscription: sub || { status: 'None' },
            paymentHistory: payments.transactions || []
        });
    } catch (error) {
        console.error("❌ GetUserFullProfile Error:", error);
        res.status(500).json({ success: false });
    }
};

exports.updateUserStatus = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        // Security: Whitelist allowed fields to prevent accidental or malicious escalation
        const allowedUpdates = [
            'accountStatus', 'isBanned', 'isPremium', 'premiumExpiry',
            'isVerified', 'isDeactivated', 'name', 'bio', 'gender', 'isShadowBanned'
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
        if (user?.fcmToken) {
            const result = await notificationService.sendPushNotification(user.fcmToken, req.body.title, req.body.message);
            if (result && result.isInvalidToken) {
                await User.updateOne(phoneQuery(phone), { $unset: { fcmToken: 1 } });
            }
        }
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
    try {
        const reqs = await VerificationRequest.find({ status: 'Pending' }).sort({ submittedAt: -1 }).lean();

        // Enrich with User Data
        const enriched = await Promise.all(reqs.map(async (r) => {
            const user = await User.findOne(phoneQuery(r.userPhone)).select('name profileImages');
            return {
                ...r,
                userName: user ? user.name : 'Unknown User',
                profileImage: user && user.profileImages?.length ? user.profileImages[0] : null
            };
        }));

        res.json(enriched);
    } catch (e) {
        console.error("GetVerificationRequests Error:", e);
        res.status(500).json([]);
    }
};

exports.rejectVerification = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const { reason } = req.body;

        await VerificationRequest.findOneAndUpdate(
            { userPhone: new RegExp(phone + '$') },
            { status: 'Rejected', reviewedAt: new Date(), adminId: req.admin?.id }
        );

        await logAction(req, "Reject Identity", phone, `Reason: ${reason || 'Incomplete profile'}`);

        const io = req.app.get('socketio');
        if (io) {
            io.to(`user_${phone}`).emit('verification_update', { status: 'Rejected', reason });
        }

        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
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
                const result = await notificationService.sendPushNotification(
                    u.fcmToken,
                    title || "Broadcast",
                    message,
                    { type: 'broadcast' }
                );
                if (result && result.success) {
                    successCount++;
                } else if (result && result.isInvalidToken) {
                    await User.updateOne({ _id: u._id }, { $unset: { fcmToken: 1 } });
                }
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

        const phones = Object.keys(pMap);
        const users = await User.find({
            $or: phones.map(p => ({ phone: new RegExp(p + '$') }))
        }).select('phone name isOnline');

        for (const user of users) {
            const normalizedUserPhone = normalize(user.phone);
            if (pMap[normalizedUserPhone]) {
                pMap[normalizedUserPhone].name = user.name;
                pMap[normalizedUserPhone].isOnline = user.isOnline;
            }
        }

        // Final cleanup for results
        const result = Object.values(pMap).map(chat => ({
            ...chat,
            name: chat.name || chat.phone, // Fallback to phone if name is missing
            isOnline: chat.isOnline || false
        }));

        res.json(result);
    } catch (e) {
        console.error("getUserInboxes Error:", e);
        res.status(500).json([]);
    }
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
        const { key, value } = req.body;
        await Config.findOneAndUpdate({ key }, { value, updatedAt: new Date() }, { upsert: true });

        // Auto-broadcast for critical configs
        if (key === 'review_mode_config' || key === 'payment_settings' || key === 'google_play_settings') {
            const io = req.app.get('socketio');
            if (io) {
                io.emit('premium_status_refresh', { key, timestamp: new Date() });
                console.log(`📢 Config Broadcast: ${key} updated.`);
            }
        }

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
        const { filter, reportedOnly } = req.query;
        let userQuery = { profileImages: { $exists: true, $not: { $size: 0 } } };
        let msgQuery = { type: 'image' };

        if (filter) {
            const pQ = new RegExp(filter + '$');
            userQuery = { phone: pQ, profileImages: { $exists: true, $not: { $size: 0 } } };
            msgQuery = { senderPhone: pQ, type: 'image' };
        }

        const [users, messages] = await Promise.all([
            User.find(userQuery, 'phone profileImages name updatedAt'),
            Message.find(msgQuery, 'senderPhone imageUrl timestamp').sort({ timestamp: -1 }).limit(filter ? 500 : 100)
        ]);

        let allMedia = [];
        users.forEach(u => u.profileImages.forEach(img => {
            allMedia.push({
                url: img,
                owner: normalize(u.phone),
                ownerName: u.name,
                type: 'Profile',
                timestamp: u.updatedAt || new Date()
            });
        }));

        messages.forEach(m => {
            if (m.imageUrl) {
                allMedia.push({
                    url: m.imageUrl,
                    owner: normalize(m.senderPhone),
                    type: 'Chat',
                    timestamp: m.timestamp
                });
            }
        });

        res.json({
            success: true,
            media: allMedia.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
        });
    } catch (e) {
        console.error("GetAllMedia Error:", e);
        res.status(500).json({ success: false });
    }
};

exports.getUserTimeline = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const pQ = new RegExp(phone + '$');

        const [user, firstMsg, analytics, reports, blocks, payments] = await Promise.all([
            User.findOne(phoneQuery(phone)),
            Message.findOne({ senderPhone: pQ }).sort({ timestamp: 1 }).lean(),
            AnalyticsEvent.find({ distinctId: pQ }).sort({ timestamp: 1 }).lean(),
            Report.find({ reportedPhone: pQ }).sort({ timestamp: -1 }).lean(),
            Block.find({ blockedPhone: pQ }).sort({ timestamp: -1 }).lean(),
            revenueService.getPaymentHistory({ userPhone: pQ }, 1, 50)
        ]);

        if (!user) return res.status(404).json({ success: false });

        let timeline = [];

        // 1. Account Creation
        timeline.push({
            type: 'account_created',
            title: 'Account Created',
            description: 'User registered on the platform',
            timestamp: user.createdAt,
            icon: 'fa-user-plus',
            color: 'text-blue-500'
        });

        // 2. Analytics Events
        analytics.forEach(ev => {
            let title = ev.type.split('_').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
            let icon = 'fa-fingerprint';
            let color = 'text-slate-400';

            if (ev.type === 'otp_verified') { icon = 'fa-shield-check'; color = 'text-emerald-500'; }
            else if (ev.type === 'onboarding_completed') { icon = 'fa-check-circle'; color = 'text-blue-400'; }
            else if (ev.type === 'premium_activated') { icon = 'fa-crown'; color = 'text-orange-500'; title = 'Premium Membership Activated'; }

            timeline.push({
                type: ev.type,
                title,
                description: `System event: ${ev.type}`,
                timestamp: ev.timestamp,
                icon,
                color
            });
        });

        // 3. First Interaction
        if (firstMsg) {
            timeline.push({
                type: 'first_message',
                title: 'First Message Sent',
                description: 'User initiated their first conversation',
                timestamp: firstMsg.timestamp,
                icon: 'fa-paper-plane',
                color: 'text-purple-500'
            });
        }

        // 4. Payments
        if (payments && payments.transactions) {
            payments.transactions.forEach(p => {
                if (p.status === 'Captured' || p.status === 'success') {
                    timeline.push({
                        type: 'payment_success',
                        title: `Payment Success (₹${p.amount})`,
                        description: `Order ID: ${p.orderId || 'N/A'}`,
                        timestamp: p.createdAt,
                        icon: 'fa-credit-card',
                        color: 'text-emerald-500'
                    });
                }
            });
        }

        // 5. Reports & Blocks (Negative Events)
        reports.forEach(r => {
            timeline.push({
                type: 'reported',
                title: 'User Reported',
                description: `Reported for: ${r.category} - "${r.description}"`,
                timestamp: r.timestamp,
                icon: 'fa-flag',
                color: 'text-red-500'
            });
        });

        blocks.forEach(b => {
            timeline.push({
                type: 'blocked',
                title: 'User Blocked',
                description: `Blocked by another user. Reason: ${b.reason}`,
                timestamp: b.timestamp,
                icon: 'fa-user-slash',
                color: 'text-orange-600'
            });
        });

        // Sort everything by time descending
        timeline.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

        res.json({ success: true, timeline });
    } catch (e) {
        console.error("Timeline Error:", e);
        res.status(500).json({ success: false });
    }
};
