const Message = require('../models/Message');
const User = require('../../users/models/User');
const Block = require('../models/Block');
const RecentPhoto = require('../models/RecentPhoto');
const Review = require('../../review/models/Review');
const ConversationMetadata = require('../models/ConversationMetadata');
const Conversation = require('../models/Conversation');
const { updateConversationSummary, resetUnreadCount } = require('../utils/chatUtils');
const { calculateDistance } = require('../../../shared/utils/locationUtils');
const { normalize, phoneQuery } = require('../../../shared/utils/phoneUtils');
const path = require('path');
const fs = require('fs');
const jwt = require('jsonwebtoken');

exports.getInbox = async (req, res) => {
    try {
        let phone = normalize(req.params.phone);
        if (req.user && !req.user.role) phone = normalize(req.user.phone);

        const page = Math.max(1, parseInt(req.query.page || 1));
        const limit = Math.max(1, parseInt(req.query.limit || 20));
        const skip = (page - 1) * limit;

        const variations = [phone, `+91${phone}`, `91${phone}`];

        // 1. Fetch current user coords once
        const caller = await User.findOne({ phone: { $in: variations } }, 'lat lng location').lean();
        const userLat = caller?.lat || caller?.location?.coordinates?.[1];
        const userLng = caller?.lng || caller?.location?.coordinates?.[0];

        // 2. Optimized Aggregation for Inbox (Scales to millions of records)
        const conversations = await Conversation.find({ userPhone: { $in: variations } })
            .sort({ 'lastMessage.timestamp': -1 })
            .skip(skip)
            .limit(limit)
            .lean();

        if (conversations.length === 0) {
            return res.json({ totalUnread: 0, chats: [] });
        }

        const partnerPhones = conversations.map(c => c.partnerPhone);
        const searchVariations = partnerPhones.reduce((acc, p) => {
            const n = normalize(p);
            acc.push(n, `+91${n}`, `91${n}`);
            return acc;
        }, []);

        // 3. Parallel fetch of required supporting data
        const [partners, blocks, metadata, unreadAgg] = await Promise.all([
            User.find({ phone: { $in: searchVariations } }, 'phone name isOnline isVerified city area position lat lng location isCreator').lean(),
            Block.find({
                $or: [
                    { blockerPhone: phone, blockedPhone: { $in: partnerPhones } },
                    { blockerPhone: { $in: partnerPhones }, blockedPhone: phone }
                ]
            }).lean(),
            ConversationMetadata.find({ phone: phone, partnerPhone: { $in: partnerPhones } }).lean(),
            page === 1 ? Conversation.aggregate([{ $match: { userPhone: phone } }, { $group: { _id: null, total: { $sum: "$unreadCount" } } }]) : Promise.resolve([])
        ]);

        const userMap = {}; partners.forEach(u => userMap[normalize(u.phone)] = u);
        const metaMap = {}; metadata.forEach(m => metaMap[normalize(m.partnerPhone)] = m);

        // Redis-based real-time online status for everyone in the inbox
        const redis = req.app.get('redis');
        let onlinePhones = [];
        try {
            if (redis) onlinePhones = await redis.sMembers('online_users');
        } catch (err) {
            console.error("Redis Inbox Status Error:", err.message);
        }
        const onlineSet = new Set(onlinePhones);

        const chats = conversations.map(conv => {
            const other = normalize(conv.partnerPhone);
            const u = userMap[other] || {};
            const meta = metaMap[other] || {};
            const block = blocks.find(b => (normalize(b.blockerPhone) === phone && normalize(b.blockedPhone) === other) || (normalize(b.blockerPhone) === other && normalize(b.blockedPhone) === phone));

            const uLat = u.lat || u.location?.coordinates?.[1];
            const uLng = u.lng || u.location?.coordinates?.[0];
            const distStr = (userLat && userLng && uLat && uLng) ? calculateDistance(userLat, userLng, uLat, uLng) : "";

            return {
                phone: other,
                msg: conv.lastMessage?.message || '',
                type: conv.lastMessage?.type || 'text',
                timestamp: conv.lastMessage?.timestamp || conv.updatedAt || new Date(),
                name: u.name || 'User',
                unread: conv.unreadCount || 0,
                isOnline: onlineSet.has(other) || u.isOnline || false,
                isVerified: u.isVerified || false,
                isBlocked: !!block,
                iBlocked: block?.blockerPhone === phone,
                city: (u.area || u.city || 'Nearby'),
                distance: distStr,
                position: u.position || '',
                isFavourite: meta.isFavourite || false,
                isMuted: meta.isMuted || false,
                isHidden: meta.isHidden || false,
                lastClearedAt: meta.lastClearedAt,
                isCreator: u.isCreator || false
            };
        }).filter(c => !c.isHidden || (new Date(c.timestamp) > new Date(c.lastClearedAt || 0)));

        let totalUnread = unreadAgg.length > 0 ? unreadAgg[0].total : 0;
        res.json({ totalUnread, chats });
    } catch (e) {
        console.error("Inbox Scale Error:", e);
        res.status(500).json({ chats: [], totalUnread: 0 });
    }
};

exports.getChatHistory = async (req, res) => {
    try {
        const p1 = normalize(req.params.p1);
        const p2 = normalize(req.params.p2);
        const { page = 1, limit = 50 } = req.query;

        // Match all possible Room ID variations (Legacy + Current)
        const roomId = [p1, p2].sort().join('_');
        const possibleRoomIds = [
            roomId,
            p1 + '_' + p2,
            p2 + '_' + p1,
            `+91${p1}_+91${p2}`,
            `+91${p2}_+91${p1}`,
            `+91${p1}_${p2}`,
            `${p1}_+91${p2}`,
            `+91${p2}_${p1}`,
            `${p2}_+91${p1}`
        ];

        const [chats, block, partner, existingReview] = await Promise.all([
            Message.find({
                roomId: { $in: possibleRoomIds },
                deletedBy: { $nin: [p1, `+91${p1}`, `91${p1}`] } // Robust deletedBy check
            })
                .sort({ timestamp: -1 })
                .skip((parseInt(page) - 1) * parseInt(limit))
                .limit(parseInt(limit)),
            Block.findOne({ $or: [{ blockerPhone: p1, blockedPhone: p2 }, { blockerPhone: p2, blockedPhone: p1 }] }),
            User.findOne(phoneQuery(p2), 'isDeactivated accountStatus'),
            parseInt(page) === 1 ? Review.findOne({ reviewerPhone: p1, reviewedPhone: p2 }) : Promise.resolve(null)
        ]);

        const messages = chats.reverse();
        const isBlocked = !!block;
        const blockerPhone = block ? block.blockerPhone : null;
        const isPartnerDeactivated = partner ? (partner.isDeactivated || partner.accountStatus === 'Deactivated') : false;
        const hasReviewed = !!existingReview;

        if (parseInt(page) === 1) {
            res.json({
                messages,
                isBlocked,
                blockerPhone,
                isPartnerDeactivated,
                hasReviewed
            });
        } else {
            res.json(messages);
        }
    } catch (e) {
        res.status(500).json(req.query.page > 1 ? [] : { messages: [] });
    }
};

exports.handleFileUpload = async (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ success: false });
        const fileUrl = `/api/media/${req.file.filename}`;

        // Security: Use phone from token if available, otherwise from body
        const phone = (req.user && !req.user.role) ? req.user.phone : normalize(req.body.phone || req.query.phone);
        const type = req.body.type || req.query.type;

        if (phone && (type === 'image' || type === 'video')) {
            await new RecentPhoto({ phone, imageUrl: fileUrl }).save();
        }
        res.json({ success: true, imageUrl: fileUrl });
    } catch (err) { res.status(500).json({ success: false }); }
};

exports.serveSecureMedia = async (req, res) => {
    try {
        const filename = req.params.filename;
        // Security: Prevent path traversal (e.g. ../../etc/passwd)
        if (filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
            return res.status(403).send("Invalid filename");
        }

        const filePath = path.join(__dirname, '../../../../uploads', filename);
        const MASTER_SECRET = process.env.MASTER_SECRET || 'GOGO_SECURE_ACCESS_2024_PROD';
        const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

        let authorized = false;

        // 1. Check for Master Secret (Legacy/Internal)
        if (req.headers['x-gogo-secret'] === MASTER_SECRET || req.query.token === MASTER_SECRET) {
            authorized = true;
        }

        // 2. Check for valid JWT (Admin or User)
        if (!authorized) {
            const authHeader = req.headers.authorization || (req.query.auth ? `Bearer ${req.query.auth}` : null);
            if (authHeader) {
                try {
                    const token = authHeader.split(' ')[1];
                    jwt.verify(token, JWT_SECRET);
                    authorized = true;
                } catch (err) {}
            }
        }

        if (!authorized) return res.status(403).send("Unauthorized");

        if (fs.existsSync(filePath)) {
            // Uploaded media is content-addressed by a timestamped filename that never
            // changes in place, so it's safe to cache aggressively client-side — this
            // is what lets repeat views of the same photo (e.g. a creator's card ->
            // profile -> chat DP) skip hitting the server entirely, which matters a
            // lot once this is serving millions of users.
            res.set('Cache-Control', 'public, max-age=2592000, immutable'); // 30 days
            res.sendFile(filePath);
        } else {
            res.status(404).send("Not found");
        }
    } catch (e) { res.status(500).send("Error"); }
};

exports.markSeen = async (req, res) => {
    try {
        let m = req.body.myPhone;
        // Security: Ensure user can only mark their own chats as seen
        if (req.user && !req.user.role) m = req.user.phone;

        m = normalize(m);
        const o = normalize(req.body.otherPhone);

        const possibleRoomIds = [
            [m, o].sort().join('_'),
            m + '_' + o,
            o + '_' + m,
            `+91${m}_+91${o}`,
            `+91${o}_+91${m}`,
            `+91${m}_${o}`,
            `${m}_+91${o}`,
            `+91${o}_${m}`,
            `${o}_+91${m}`
        ];

        const phoneVariations = [m, `+91${m}`, `91${m}`];

        // SECURITY FIX: Only mark normal messages as 'Opened' (Seen).
        await Message.updateMany({
            roomId: { $in: possibleRoomIds },
            receiverPhone: { $in: phoneVariations },
            isOpened: false,
            isViewOnce: false
        }, { isOpened: true, isDelivered: true });

        // For View Once, just ensure they are marked as Delivered
        await Message.updateMany({
            roomId: { $in: possibleRoomIds },
            receiverPhone: { $in: phoneVariations },
            isDelivered: false,
            isViewOnce: true
        }, { isDelivered: true });

        await resetUnreadCount(m, o);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.updateMetadata = async (req, res) => {
    try {
        let { phone, partnerPhone, isMuted, isFavourite, isHidden } = req.body;
        // Security: Ensure user can only update their own metadata
        if (req.user && !req.user.role) phone = req.user.phone;

        const p = normalize(phone), pp = normalize(partnerPhone);
        const update = {};
        if (isMuted !== undefined) update.isMuted = isMuted;
        if (isFavourite !== undefined) update.isFavourite = isFavourite;
        if (isHidden !== undefined) {
            update.isHidden = isHidden;
            if (isHidden) update.lastClearedAt = new Date();
        }
        const meta = await ConversationMetadata.findOneAndUpdate({ phone: p, partnerPhone: pp }, update, { upsert: true, new: true });
        res.json({ success: true, meta });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.blockUser = async (req, res) => {
    try {
        let b1 = req.body.blockerPhone;
        // Security: Ensure user can only block as themselves
        if (req.user && !req.user.role) b1 = req.user.phone;

        b1 = normalize(b1);
        const b2 = normalize(req.body.blockedPhone);
        await Block.findOneAndUpdate({ blockerPhone: b1, blockedPhone: b2 }, { reason: req.body.reason, timestamp: new Date() }, { upsert: true });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.unblockUser = async (req, res) => {
    try {
        let b1 = req.body.blockerPhone;
        // Security: Ensure user can only unblock as themselves
        if (req.user && !req.user.role) b1 = req.user.phone;

        b1 = normalize(b1);
        const b2 = normalize(req.body.blockedPhone);
        await Block.findOneAndDelete({ blockerPhone: b1, blockedPhone: b2 });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.checkBlock = async (req, res) => {
    try {
        const p1 = normalize(req.params.p1), p2 = normalize(req.params.p2);
        const b = await Block.findOne({ $or: [{ blockerPhone: p1, blockedPhone: p2 }, { blockerPhone: p2, blockedPhone: p1 }] });
        res.json({ success: true, isBlocked: !!b, blockerPhone: b ? b.blockerPhone : null });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getRecentPhotos = async (req, res) => {
    try {
        let phone = normalize(req.params.phone);
        // IDOR Prevention: Always prefer token phone for users
        if (req.user && !req.user.role) phone = normalize(req.user.phone);

        const pQ = phoneQuery(phone);
        res.json({ success: true, photos: await RecentPhoto.find(pQ).sort({ timestamp: -1 }).limit(20) });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getBlockedList = async (req, res) => {
    try {
        let phone = normalize(req.params.phone);
        // IDOR Prevention: Always prefer token phone for users
        if (req.user && !req.user.role) phone = normalize(req.user.phone);

        const phoneVariations = [phone, `+91${phone}`, `91${phone}`];
        const blocks = await Block.find({ blockerPhone: { $in: phoneVariations } }).lean();
        const partnerPhones = blocks.map(b => b.blockedPhone);

        const searchPhones = [];
        partnerPhones.forEach(p => {
            const n = normalize(p);
            searchPhones.push(n);
            searchPhones.push(`+91${n}`);
            searchPhones.push(`91${n}`);
        });

        const blockedUsers = await User.find({ phone: { $in: searchPhones } }, 'phone name profileImages').lean();

        const result = blockedUsers.map(u => ({
            phone: u.phone,
            name: u.name,
            profileImage: u.profileImages && u.profileImages.length > 0 ? u.profileImages[0] : null
        }));

        res.json({ success: true, blockedUsers: result });
    } catch (e) {
        res.status(500).json({ success: false, message: e.message });
    }
};

exports.deletePhoto = async (req, res) => {
    try {
        const photo = await RecentPhoto.findById(req.params.messageId);
        if (photo) {
            // IDOR Check: Ensure user owns the photo or is admin
            if (req.user && !req.user.role && normalize(req.user.phone) !== normalize(photo.phone)) {
                return res.status(403).json({ success: false, message: "Unauthorized" });
            }

            const filePath = path.join(process.cwd(), 'uploads', photo.imageUrl.split('/').pop());
            if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
            await RecentPhoto.findByIdAndDelete(req.params.messageId);
        }
        res.json({ success: true });
    } catch (e) { res.json({ success: true }); }
};

// Atomically spends one call credit for a fake voice-call attempt to a
// creator. The $gt:0 guard makes this race-safe under double-taps — no
// separate read-then-write, so credits can never go negative.
exports.checkCallCredit = async (req, res) => {
    try {
        const myPhone = req.user?.phone ? normalize(req.user.phone) : normalize(req.body.phone);
        if (!myPhone) return res.status(400).json({ success: false, allowed: false, message: "Phone is required" });

        const updated = await User.findOneAndUpdate(
            { ...phoneQuery(myPhone), callCredits: { $gt: 0 } },
            { $inc: { callCredits: -1 } },
            { new: true }
        );

        if (!updated) {
            return res.json({ success: true, allowed: false, remainingCredits: 0 });
        }
        res.json({ success: true, allowed: true, remainingCredits: updated.callCredits });
    } catch (e) {
        console.error("checkCallCredit Error:", e);
        res.status(500).json({ success: false, allowed: false, message: e.message });
    }
};

// Serves the list of pre-recorded "hello" greeting clips played during the
// simulated call preview (free-mode paywall tease and creator fake calls).
// Clips live as static files in public/audio/greetings/ so they can be
// swapped/added by dropping a new file on the server — no app release needed.
exports.getCallGreetingAudio = (req, res) => {
    try {
        const dir = path.join(process.cwd(), 'public', 'audio', 'greetings');
        if (!fs.existsSync(dir)) return res.json({ success: true, clips: [] });

        const audioExt = /\.(mp3|m4a|wav|aac|ogg)$/i;
        const clips = fs.readdirSync(dir)
            .filter((f) => audioExt.test(f))
            .map((f) => `/audio/greetings/${f}`);

        res.json({ success: true, clips });
    } catch (e) {
        console.error("getCallGreetingAudio Error:", e);
        res.json({ success: true, clips: [] });
    }
};

// Serves the list of fake-partner video clips played during Random Live
// matching (see FakeRandomCallScreen). Clips live as static files in
// public/video/randomlive/ so they can be swapped/added without an app
// release — see AdminController.getRandomLiveVideos for the admin-side
// upload/list/delete endpoints.
exports.getRandomLiveVideos = (req, res) => {
    try {
        const dir = path.join(process.cwd(), 'public', 'video', 'randomlive');
        if (!fs.existsSync(dir)) return res.json({ success: true, clips: [] });

        const videoExt = /\.(mp4|mov|webm|m4v)$/i;
        const clips = fs.readdirSync(dir)
            .filter((f) => videoExt.test(f))
            .map((f) => `/video/randomlive/${f}`);

        res.json({ success: true, clips });
    } catch (e) {
        console.error("getRandomLiveVideos Error:", e);
        res.json({ success: true, clips: [] });
    }
};

exports.deleteRecentPhotoByUrl = async (req, res) => {
    try {
        let phone = normalize(req.body.phone);
        // IDOR Prevention: Always prefer token phone for users
        if (req.user && !req.user.role) phone = normalize(req.user.phone);

        const url = req.body.imageUrl.split('?')[0];
        const photo = await RecentPhoto.findOne({ phone, imageUrl: url });
        if (photo) {
            const filePath = path.join(process.cwd(), 'uploads', url.split('/').pop());
            if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
            await RecentPhoto.deleteOne({ _id: photo._id });
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};
