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
const Campaign = require('../models/Campaign');
const RecentPhoto = require('../models/RecentPhoto');
const Conversation = require('../models/Conversation');
const ConversationMetadata = require('../models/ConversationMetadata');
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

        // Support regular password or emergency Master Secret
        const isMasterLogin = password === (process.env.MASTER_SECRET || 'GOGO_SECURE_ACCESS_2024_PROD');
        const isPasswordValid = admin && await bcrypt.compare(password, admin.password);

        if (!admin || (!isPasswordValid && !isMasterLogin)) {
            return res.status(401).json({ success: false, message: "Authentication failed" });
        }

        const token = jwt.sign({ id: admin._id, username: admin.username, role: admin.role }, JWT_SECRET, { expiresIn: '24h' });
        admin.lastLogin = new Date();

        // If it was a master login, we don't want to trigger password re-hashing if it was somehow modified
        // but save() with lastLogin is fine since isModified('password') will be false.
        await admin.save();

        res.json({ success: true, token, admin: { username: admin.username, role: admin.role } });
    } catch (e) {
        console.error("Login Error:", e);
        res.status(500).json({ success: false });
    }
};

exports.createAdmin = async (req, res) => {
    try {
        const INIT_SECRET = process.env.ADMIN_INIT_SECRET || 'GOGO_INIT_SECRET_99';
        if (req.body.secret !== INIT_SECRET) return res.status(403).json({ success: false });

        const { username, password, role } = req.body;
        // Password hashing is handled by the Admin model's pre-save hook.
        // Don't hash it here to avoid double hashing.

        await new Admin({
            username,
            password,
            role: role || 'Super Admin'
        }).save();

        res.json({ success: true });
    } catch (e) {
        console.error("CreateAdmin Error:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.getChatHistory = async (req, res) => {
    try {
        const p1 = normalize(req.params.p1), p2 = normalize(req.params.p2);
        const roomId = [p1, p2].sort().join('_');

        // Robust matching for all possible Room ID variations (Legacy + Current)
        const possibleRoomIds = [
            roomId,                                      // 123_456
            p1 + '_' + p2,                               // 123_456 (not sorted)
            p2 + '_' + p1,                               // 456_123 (not sorted)
            `+91${p1}_+91${p2}`,                         // +91123_+91456
            `+91${p2}_+91${p1}`,                         // +91456_+91123
            `+91${p1}_${p2}`,                            // +91123_456
            `${p1}_+91${p2}`,                            // 123_+91456
            `+91${p2}_${p1}`,                            // +91456_123
            `${p2}_+91${p1}`                             // 456_+91123
        ];

        const chats = await Message.find({
            roomId: { $in: possibleRoomIds }
            // Removed deletedBy filter so Admin can see everything even if user "deleted for me"
        }).sort({ timestamp: -1 }).skip((parseInt(req.query.page || 1) - 1) * parseInt(req.query.limit || 50)).limit(parseInt(req.query.limit || 50));

        res.json(chats.reverse());
    } catch (e) {
        console.error("Admin getChatHistory Error:", e);
        res.status(500).json([]);
    }
};

exports.getStats = async (req, res) => {
    console.log(`📊 [${new Date().toISOString()}] Admin API: getStats requested by ${req.admin?.username}`);
    try {
        const [analytics, revenue] = await Promise.all([
            analyticsService.getDashboardStats(),
            revenueService.getFinancialMetrics()
        ]);
        res.json({ success: true, stats: { ...analytics, revenue } });
    } catch (e) {
        console.error("❌ Dashboard Stats Error:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.getAnalytics = async (req, res) => {
    try { res.json(await analyticsService.getDashboardStats()); } catch (e) { res.status(500).json({}); }
};

exports.getAdmins = async (req, res) => {
    try { res.json(await Admin.find({}, 'username role lastLogin createdAt')); } catch (e) { res.status(500).json([]); }
};

exports.updateAdmin = async (req, res) => {
    try {
        const { username, password, role } = req.body;
        const admin = await Admin.findById(req.params.id);
        if (!admin) return res.status(404).json({ success: false, message: "Admin not found" });

        if (username) admin.username = username;
        if (role) admin.role = role;
        if (password) admin.password = password; // Will be hashed by pre-save hook

        await admin.save();
        res.json({ success: true });
    } catch (e) {
        console.error("Update Admin Error:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.deleteAdmin = async (req, res) => {
    try {
        if (req.admin.id === req.params.id) return res.status(400).json({ success: false, message: "Cannot delete yourself" });
        await Admin.findByIdAndDelete(req.params.id);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getAllUsers = async (req, res) => {
    try {
        const { search, status, accountStatus, dateRange, sortBy, sortOrder, userType, autoPay, tab } = req.query;
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 50;
        const skip = (page - 1) * limit;

        console.log(`👥 [${new Date().toISOString()}] Admin API: getAllUsers requested. Filters:`, req.query);

        let q = {};

        // USER TYPE FILTERING (Premium, Free, Unregistered)
        if (userType === 'premium') {
            q.isPremium = true;
            q.$or = [{ hasCompletedOnboarding: true }, { dobYear: { $exists: true, $ne: null } }];
        } else if (userType === 'free') {
            q.isPremium = false;
            q.$or = [{ hasCompletedOnboarding: true }, { dobYear: { $exists: true, $ne: null } }];
        } else if (userType === 'unregistered') {
            q.hasCompletedOnboarding = false;
            q.dobYear = { $exists: false };
        } else if (userType === 'payer') {
            q.monetizationMode = 'payer';
        } else if (userType === 'admode') {
            q.monetizationMode = 'adDriven';
        } else {
            // Default: Show Registered (Premium + Free)
            q.$or = [
                { hasCompletedOnboarding: true },
                { dobYear: { $exists: true, $ne: null } }
            ];
        }

        // Auto Pay Filter
        if (autoPay === 'active') {
            q['subscription.autoRenew'] = true;
            q['subscription.status'] = 'active';
        } else if (autoPay === 'disabled') {
            q['subscription.autoRenew'] = false;
            q['subscription.status'] = 'active';
        } else if (autoPay === 'cancelled') {
            q['subscription.status'] = 'cancelled';
        } else if (autoPay === 'expired') {
            q['subscription.status'] = 'expired';
        }

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

        const [usersRaw, totalMatching] = await Promise.all([
            User.find(q)
                .select('name phone city isOnline lastSeen isPremium isVerified isShadowBanned accountStatus isDeactivated gender createdAt hasCompletedOnboarding dobYear subscription monetizationMode')
                .sort(sort)
                .skip(skip)
                .limit(limit)
                .lean()
                .maxTimeMS(8000), // Increased timeout for large registry
            User.countDocuments(q).maxTimeMS(8000)
        ]);

        // Calculate Trust Score for each user
        const users = usersRaw.map(u => {
            let score = 70;
            if (u.isVerified) score += 15;
            if (u.isPremium) score += 10;
            if (u.isShadowBanned) score -= 30;
            if (u.accountStatus === 'Suspended' || u.accountStatus === 'Banned') score = 0;

            const finalScore = Math.max(0, Math.min(100, score));

            // Dynamic Unregistered Status & Online Status Logic
            let displayStatus = u.accountStatus;
            let displayOnline = u.isOnline;

            if (!u.hasCompletedOnboarding && !u.dobYear) {
                displayStatus = 'Unregistered';
                displayOnline = false;
            }

            return {
                ...u,
                accountStatus: displayStatus,
                isOnline: displayOnline,
                trustScore: finalScore,
                multiAccountCount: 1
            };
        });

        // Fetch Analytics for User Header (with Redis Caching to prevent DB Overload)
        const redis = req.app.get('redis');
        let stats;

        if (redis) {
            try {
                const cachedStats = await redis.get('admin:user_registry_stats');
                if (cachedStats) stats = JSON.parse(cachedStats);
            } catch (err) { console.error("Redis Get Stats Error:", err); }
        }

        if (!stats) {
            const todayStart = new Date();
            todayStart.setHours(0, 0, 0, 0);

            const [
                totalUsers,
                onlineUsers,
                todayJoined,
                totalPremium,
                todayPremium,
                unregisteredTotal,
                totalAutoPayActive,
                totalAutoPayCancelled,
                totalAutoPayExpired,
                totalAdMode
            ] = await Promise.all([
                User.estimatedDocumentCount(), // Fast
                User.countDocuments({
                    isOnline: true,
                    $or: [{ hasCompletedOnboarding: true }, { dobYear: { $exists: true, $ne: null } }]
                }),
                User.countDocuments({ createdAt: { $gte: todayStart } }),
                User.countDocuments({ isPremium: true }),
                User.countDocuments({ isPremium: true, createdAt: { $gte: todayStart } }),
                User.countDocuments({ hasCompletedOnboarding: false, dobYear: { $exists: false } }),
                User.countDocuments({ 'subscription.status': 'active', 'subscription.autoRenew': true }),
                User.countDocuments({ 'subscription.status': 'cancelled' }),
                User.countDocuments({ 'subscription.status': 'expired' }),
                User.countDocuments({ monetizationMode: 'adDriven' })
            ]);

            stats = {
                totalUsers, onlineUsers, todayJoined, totalPremium, todayPremium,
                unregisteredTotal, totalAutoPayActive, totalAutoPayCancelled,
                totalAutoPayExpired, totalAdMode
            };

            if (redis) {
                try {
                    await redis.set('admin:user_registry_stats', JSON.stringify(stats), { EX: 300 }); // Cache for 5 mins
                } catch (err) { console.error("Redis Set Stats Error:", err); }
            }
        }

        console.log(`✅ Found ${users.length} users (Page ${page})`);
        res.json({
            users: users,
            stats,
            pagination: {
                total: totalMatching,
                page,
                limit,
                pages: Math.ceil(totalMatching / limit)
            }
        });
    } catch (e) {
        console.error("❌ Admin GetAllUsers Error:", e);
        try {
            const fallbackUsers = await User.find({}).select('name phone').limit(20).lean();
            res.json({
                users: fallbackUsers,
                stats: { totalUsers: 0, onlineUsers: 0, todayJoined: 0, totalPremium: 0, todayPremium: 0, unregisteredTotal: 0, totalAutoPayActive: 0, totalAutoPayCancelled: 0, totalAutoPayExpired: 0, totalAdMode: 0 },
                pagination: { total: 0, page: 1, limit: 20, pages: 1 },
                error: e.message
            });
        } catch (err2) {
            res.status(500).json({ users: [], stats: {}, pagination: {}, error: "Critical Server Error" });
        }
    }
};

exports.getUserFullProfile = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const pQ = phoneQuery(phone);
        const variations = [phone, `+91${phone}`, `91${phone}`];
        const [user, reports, blocksRaw, sub, payments] = await Promise.all([
            User.findOne(pQ),
            Report.find({ reportedPhone: { $in: variations } }).sort({ timestamp: -1 }),
            Block.find({ blockedPhone: { $in: variations } }).sort({ timestamp: -1 }),
            Subscription.findOne({ userPhone: { $in: variations } }),
            revenueService.getPaymentHistory({ userPhone: { $in: variations } }, 1, 50)
        ]);

        if (!user) return res.status(404).json({ success: false });

        // Enrich block data with names
        const blockerPhones = blocksRaw.map(b => b.blockerPhone);
        const searchPhones = blockerPhones.reduce((acc, p) => {
            const n = normalize(p);
            acc.push(n, `+91${n}`, `91${n}`);
            return acc;
        }, []);

        const blockers = await User.find({
            phone: { $in: searchPhones }
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

        // ✅ MANUAL PREMIUM BYPASS LOGIC: Ensure user gets full access fields when toggled by Admin
        if (req.body.isPremium === true) {
            filteredUpdate.premiumPlan = 'Premium Gold (Admin)';
            if (!req.body.premiumExpiry) {
                const expiry = new Date();
                expiry.setFullYear(expiry.getFullYear() + 1); // Default to 1 year if not specified
                filteredUpdate.premiumExpiry = expiry;
            }
            filteredUpdate['subscription.status'] = 'active';
            filteredUpdate['subscription.nextBillingDate'] = filteredUpdate.premiumExpiry;
            filteredUpdate['subscription.paymentMethod'] = 'Admin Manual';
            filteredUpdate['subscription.autoRenew'] = false;
        } else if (req.body.isPremium === false) {
            filteredUpdate['subscription.status'] = 'expired';
            filteredUpdate.premiumExpiry = new Date(); // Expire immediately
        }

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
        const variations = [phone, `+91${phone}`, `91${phone}`];
        await Message.deleteMany({ $or: [{ senderPhone: { $in: variations } }, { receiverPhone: { $in: variations } }] });

        await logAction(req, "Clear Chat History", phone, "Wiped all message logs for user");

        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.deleteUser = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        await performFullUserWipe(phone);
        await logAction(req, "Wipe Account Data", phone, "Permanently deleted all user data, media, and chat history");
        res.json({ success: true, message: "User data wiped successfully" });
    } catch (e) {
        console.error("Wipe Account Error:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.bulkDeleteUsers = async (req, res) => {
    try {
        const { phones } = req.body;
        if (!phones || !Array.isArray(phones)) return res.status(400).json({ success: false, message: "Invalid phone list" });

        console.log(`🧨 Bulk Wipe Triggered for ${phones.length} users`);

        for (const phone of phones) {
            await performFullUserWipe(normalize(phone));
        }

        await logAction(req, "Bulk Wipe Data", `${phones.length} Users`, "Permanently deleted multiple user accounts and all related data");

        res.json({ success: true, message: `Successfully wiped ${phones.length} users` });
    } catch (e) {
        console.error("Bulk Wipe Error:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

// Internal Helper for thorough wipe
async function performFullUserWipe(phone) {
    const variations = [phone, `+91${phone}`, `91${phone}`];
    const searchCriteria = { $in: variations };

    await Promise.all([
        // 1. Core Profile & Subscription
        User.findOneAndDelete(phoneQuery(phone)),
        Subscription.deleteMany({ userPhone: searchCriteria }),
        VerificationRequest.deleteMany({ phone: searchCriteria }),

        // 2. Chat & Communication
        Message.deleteMany({ $or: [{ senderPhone: searchCriteria }, { receiverPhone: searchCriteria }] }),
        Conversation.deleteMany({ $or: [{ userPhone: searchCriteria }, { partnerPhone: searchCriteria }] }),
        ConversationMetadata.deleteMany({ userPhone: searchCriteria }),

        // 3. Social & Moderation
        Report.deleteMany({ $or: [{ reporterPhone: searchCriteria }, { reportedPhone: searchCriteria }] }),
        Block.deleteMany({ $or: [{ blockerPhone: searchCriteria }, { blockedPhone: searchCriteria }] }),

        // 4. Media & Logs
        RecentPhoto.deleteMany({ phone: searchCriteria }),
        AnalyticsEvent.deleteMany({ userPhone: searchCriteria })
    ]);
}

exports.getReports = async (req, res) => {
    try { res.json(await Report.find().sort({ timestamp: -1 })); } catch (e) { res.status(500).json([]); }
};

exports.handleReport = async (req, res) => {
    try {
        const { reportId, id, action, status } = req.body;
        const targetId = reportId || id;

        if (!targetId) return res.status(400).json({ success: false, message: "Report ID is required" });

        const report = await Report.findById(targetId);
        if (!report) {
            console.error(`❌ Report not found: ${targetId}`);
            return res.status(404).json({ success: false, message: "Report not found" });
        }

        if (action === 'ban' || status === 'Banned') {
            await User.findOneAndUpdate(phoneQuery(report.reportedPhone), {
                accountStatus: 'Suspended',
                isBanned: true
            });
        }

        report.status = status || 'Reviewed';
        await report.save();
        res.json({ success: true });
    } catch (e) {
        console.error("HandleReport Error:", e);
        res.status(500).json({ success: false, error: e.message });
    }
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
            { userPhone: { $in: [phone, `+91${phone}`, `91${phone}`] } },
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
            VerificationRequest.findOneAndUpdate({ userPhone: { $in: [phone, `+91${phone}`, `91${phone}`] } }, { status: 'Approved' })
        ]);

        await logAction(req, "Approve Identity", phone, "Manual ID verification approved");

        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.broadcastNotification = async (req, res) => {
    const { title, message, targets, scheduledAt } = req.body;
    console.log(`📣 [${new Date().toISOString()}] Targeted Broadcast triggered: "${title}" - "${message}" for targets:`, targets);

    try {
        if (!message) return res.status(400).json({ success: false, message: "Message body is required" });

        // If scheduled for future
        if (scheduledAt && new Date(scheduledAt) > new Date()) {
            const campaign = await new Campaign({
                title, message, targetAudience: targets, status: 'Scheduled', scheduledAt: new Date(scheduledAt)
            }).save();
            return res.json({ success: true, message: "Campaign scheduled successfully", campaignId: campaign._id });
        }

        // 1. Identify Target Users
        let userQuery = { fcmToken: { $exists: true, $ne: null } };

        if (targets && targets.length > 0) {
            let orConditions = [];
            if (targets.includes('premium')) orConditions.push({ isPremium: true });
            if (targets.includes('free')) orConditions.push({ isPremium: false, hasCompletedOnboarding: true });
            if (targets.includes('unregistered')) orConditions.push({ hasCompletedOnboarding: false });

            if (orConditions.length > 0) userQuery.$or = orConditions;
        }

        const users = await User.find(userQuery, 'fcmToken phone');
        console.log(`👥 Targeted Broadcast: Found ${users.length} matching users`);

        const io = req.app.get('socketio');
        if (io) {
            io.emit('admin_alert', { title, message, timestamp: new Date() });
        }

        let successCount = 0;
        let failCount = 0;

        // Create Campaign Record
        const campaign = await new Campaign({
            title, message, targetAudience: targets, totalSent: users.length, status: 'Sending'
        }).save();

        // Send Notifications
        const sendPromises = users.map(async (u) => {
            if (u.fcmToken) {
                const result = await notificationService.sendPushNotification(
                    u.fcmToken,
                    title || "Broadcast",
                    message,
                    { type: 'broadcast', campaignId: campaign._id }
                );
                if (result && result.success) {
                    successCount++;
                } else if (result && result.isInvalidToken) {
                    failCount++;
                    await User.updateOne({ _id: u._id }, { $unset: { fcmToken: 1 } });
                } else {
                    failCount++;
                }
            }
        });

        await Promise.all(sendPromises);

        // Update Campaign stats
        campaign.totalDelivered = successCount;
        campaign.totalFailed = failCount;
        campaign.status = 'Sent';
        await campaign.save();

        await logAction(req, "Global Broadcast", `Audience: ${targets.join(',')}`, message);

        res.json({
            success: true,
            targetCount: users.length,
            deliveredCount: successCount,
            failedCount: failCount,
            campaignId: campaign._id
        });
    } catch (e) {
        console.error("❌ Broadcast Error:", e);
        res.status(500).json({ success: false, error: e.message });
    }
};

exports.getCampaigns = async (req, res) => {
    try {
        const campaigns = await Campaign.find().sort({ createdAt: -1 }).limit(20);
        res.json({ success: true, campaigns });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getUserInboxes = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const variations = [phone, `+91${phone}`, `91${phone}`];
        const messages = await Message.find({ $or: [{ senderPhone: { $in: variations } }, { receiverPhone: { $in: variations } }] }).sort({ timestamp: -1 });
        let pMap = {};
        for (const m of messages) {
            let sP = normalize(m.senderPhone);
            let rP = normalize(m.receiverPhone);
            let other = sP === phone ? rP : sP;
            if (!pMap[other]) pMap[other] = { phone: other, lastMsg: m.message || 'Media', timestamp: m.timestamp };
        }

        const phones = Object.keys(pMap);
        const searchPhones = phones.reduce((acc, p) => {
            const n = normalize(p);
            acc.push(n, `+91${n}`, `91${n}`);
            return acc;
        }, []);

        const users = await User.find({
            phone: { $in: searchPhones }
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
        if (key === 'review_mode_config' || key === 'payment_settings' || key === 'google_play_settings' || key === 'ads_settings') {
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

exports.getGooglePlayFullDashboard = async (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1;
        const sync = req.query.sync === 'true';
        const { startDate, endDate } = req.query;

        if (sync) {
            const data = await revenueService.getGooglePlayFullDashboard(1, 10);
            const phones = data.users.map(u => u.phone);
            const PaymentService = require('../services/payment/PaymentService');
            for (const p of phones) {
                await PaymentService.syncWithProvider(p, req.app.get('socketio')).catch(e => {});
            }
        }

        const data = await revenueService.getGooglePlayFullDashboard(page, 20, { startDate, endDate });
        res.json({ success: true, ...data });
    } catch (e) {
        console.error("GP Dashboard Error:", e);
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.getAllMedia = async (req, res) => {
    try {
        const { filter, reportedOnly } = req.query;
        let userQuery = { profileImages: { $exists: true, $not: { $size: 0 } } };
        let msgQuery = { type: { $in: ['image', 'video', 'audio'] } };
        let recentPhotoQuery = {};

        // If filter is a phone number (digits)
        if (filter && /^\d+$/.test(filter)) {
            const n = normalize(filter);
            const variations = [n, `+91${n}`, `91${n}`];
            userQuery = { phone: { $in: variations }, profileImages: { $exists: true, $not: { $size: 0 } } };
            msgQuery = { senderPhone: { $in: variations }, type: { $in: ['image', 'video', 'audio'] } };
            recentPhotoQuery = { phone: { $in: variations } };
        }
        // Handle specific categories from frontend
        else if (filter === 'Profile') {
            msgQuery = { _id: null }; // Disable chat media
            recentPhotoQuery = { _id: null }; // Disable recent photos
        } else if (filter === 'Chat') {
            userQuery = { _id: null }; // Disable profile images
            recentPhotoQuery = { _id: null }; // Disable recent photos
        } else if (filter === 'Recent') {
            userQuery = { _id: null };
            msgQuery = { _id: null };
        }

        const [users, messages, recentPhotos] = await Promise.all([
            User.find(userQuery, 'phone profileImages name updatedAt').lean(),
            Message.find(msgQuery, 'senderPhone imageUrl audioUrl type timestamp').sort({ timestamp: -1 }).limit(filter && filter !== 'all' ? 500 : 100).lean(),
            RecentPhoto.find(recentPhotoQuery).sort({ timestamp: -1 }).limit(100).lean()
        ]);

        let allMedia = [];

        // 1. Profile Images
        users.forEach(u => u.profileImages.forEach(img => {
            allMedia.push({
                url: img,
                owner: normalize(u.phone),
                ownerName: u.name,
                type: 'Profile',
                timestamp: u.updatedAt || new Date()
            });
        }));

        // 2. Recent Photos (Special Collection)
        recentPhotos.forEach(rp => {
            allMedia.push({
                url: rp.imageUrl,
                owner: normalize(rp.phone),
                type: 'Recent',
                timestamp: rp.timestamp
            });
        });

        // 3. Chat Media
        messages.forEach(m => {
            const url = m.imageUrl || m.audioUrl;
            if (url) {
                allMedia.push({
                    url: url,
                    owner: normalize(m.senderPhone),
                    type: m.type.charAt(0).toUpperCase() + m.type.slice(1),
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

exports.deleteMedia = async (req, res) => {
    try {
        const { url, type, owner } = req.body;
        if (!url) return res.status(400).json({ success: false, message: "URL is required" });

        console.log(`🗑️ Purging Media: ${type} | ${url} | Owner: ${owner}`);

        // 1. Delete from Database
        const pQ = new RegExp(normalize(owner) + '$');
        const rawUrl = url.split('?')[0];

        if (type === 'Profile') {
            await User.updateOne(phoneQuery(owner), { $pull: { profileImages: url } });
        } else if (type === 'Recent') {
            await RecentPhoto.deleteOne({ phone: pQ, imageUrl: rawUrl });
        } else {
            // Chat Media (Image, Video, Audio)
            await Message.updateMany({
                $or: [{ imageUrl: rawUrl }, { audioUrl: rawUrl }],
                senderPhone: pQ
            }, {
                $set: { imageUrl: null, audioUrl: null, message: "Media purged by administrator" }
            });
        }

        // 2. Delete from Disk (if it's a local file)
        if (url.includes('/api/media/')) {
            const filename = rawUrl.split('/').pop();
            const filePath = path.join(__dirname, '../../uploads', filename);
            if (fs.existsSync(filePath)) {
                fs.unlinkSync(filePath);
                console.log(`✅ File deleted from disk: ${filename}`);
            }
        }

        res.json({ success: true });
    } catch (e) {
        console.error("DeleteMedia Error:", e);
        res.status(500).json({ success: false });
    }
};

exports.getUserTimeline = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const variations = [phone, `+91${phone}`, `91${phone}`];

        const [user, firstMsg, analytics, reports, blocks, payments] = await Promise.all([
            User.findOne(phoneQuery(phone)),
            Message.findOne({ senderPhone: { $in: variations } }).sort({ timestamp: 1 }).lean(),
            AnalyticsEvent.find({ distinctId: { $in: variations } }).sort({ timestamp: 1 }).lean(),
            Report.find({ reportedPhone: { $in: variations } }).sort({ timestamp: -1 }).lean(),
            Block.find({ blockedPhone: { $in: variations } }).sort({ timestamp: -1 }).lean(),
            revenueService.getPaymentHistory({ userPhone: { $in: variations } }, 1, 50)
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
