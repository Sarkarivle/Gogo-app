const Message = require('../models/Message');
const User = require('../models/User');
const Block = require('../models/Block');
const RecentPhoto = require('../models/RecentPhoto');
const ConversationMetadata = require('../models/ConversationMetadata');
const Conversation = require('../models/Conversation');
const { updateConversationSummary, resetUnreadCount } = require('../utils/chatUtils');
const path = require('path');
const fs = require('fs');

const normalize = (p) => p ? String(p).replace(/[^0-9]/g, '') : '';

exports.getInbox = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const page = Math.max(1, parseInt(req.query.page || 1));
        const limit = Math.max(1, parseInt(req.query.limit || 50));
        const skip = (page - 1) * limit;

        // 1. Fetch conversations sorted by last message timestamp with pagination
        const [conversations, allMetadata] = await Promise.all([
            Conversation.find({ userPhone: phone })
                .sort({ 'lastMessage.timestamp': -1 })
                .skip(skip)
                .limit(limit)
                .lean(),
            ConversationMetadata.find({ phone }).lean()
        ]);

        const metaMap = {};
        allMetadata.forEach(m => metaMap[m.partnerPhone] = m);

        // 2. Filter out hidden conversations if they haven't received a new message since clearing
        const visibleConversations = conversations.filter(c => {
            if (!c.lastMessage) return false;
            const meta = metaMap[c.partnerPhone];
            if (meta && meta.isHidden) {
                return new Date(c.lastMessage.timestamp || 0).getTime() > new Date(meta.lastClearedAt || 0).getTime();
            }
            return true;
        });

        const partnerPhones = visibleConversations.map(c => c.partnerPhone);

        // 3. Fetch partners and blocks in parallel
        const [partners, blocks] = await Promise.all([
            User.find({ phone: { $in: partnerPhones } }, 'phone name isOnline isVerified city area').lean(),
            Block.find({
                $or: [
                    { blockerPhone: phone, blockedPhone: { $in: partnerPhones } },
                    { blockerPhone: { $in: partnerPhones }, blockedPhone: phone }
                ]
            }).lean()
        ]);

        const userMap = {};
        partners.forEach(u => userMap[u.phone] = u);

        const chats = visibleConversations.map(conv => {
            const other = conv.partnerPhone;
            const u = userMap[other] || {};
            const block = blocks.find(b => (b.blockerPhone === phone && b.blockedPhone === other) || (b.blockerPhone === other && b.blockedPhone === phone));

            const cleanArea = (u.area && u.area.toLowerCase() !== 'unknown') ? u.area : '';
            const cleanCity = (u.city && u.city.toLowerCase() !== 'unknown') ? u.city : '';

            return {
                phone: other,
                msg: conv.lastMessage.message,
                type: conv.lastMessage.type,
                timestamp: conv.lastMessage.timestamp,
                name: u.name || 'User',
                unread: conv.unreadCount || 0,
                isOnline: u.isOnline || false,
                isVerified: u.isVerified || false,
                isBlocked: !!block,
                iBlocked: block?.blockerPhone === phone,
                city: cleanArea || cleanCity || 'Nearby'
            };
        });

        // 4. Calculate total unread (Optional: this could be cached or kept in User model for speed)
        const totalUnread = await Conversation.aggregate([
            { $match: { userPhone: phone } },
            { $group: { _id: null, total: { $sum: "$unreadCount" } } }
        ]);

        res.json({
            totalUnread: totalUnread.length > 0 ? totalUnread[0].total : 0,
            chats
        });
    } catch (e) {
        res.status(500).json({ chats: [], totalUnread: 0 });
    }
};

exports.getChatHistory = async (req, res) => {
    try {
        const p1 = normalize(req.params.p1);
        const p2 = normalize(req.params.p2);
        const { page = 1, limit = 50 } = req.query;
        const roomId = [p1, p2].sort().join('_');

        const chats = await Message.find({ roomId, deletedBy: { $ne: p1 } })
            .sort({ timestamp: -1 })
            .skip((parseInt(page) - 1) * parseInt(limit))
            .limit(parseInt(limit));

        res.json(chats.reverse());
    } catch (e) { res.status(500).json([]); }
};

exports.handleFileUpload = async (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ success: false });
        const fileUrl = `/api/media/${req.file.filename}`;
        const phone = normalize(req.body.phone || req.query.phone);
        const type = req.body.type || req.query.type;

        if (phone && (type === 'image' || type === 'video')) {
            await new RecentPhoto({ phone, imageUrl: fileUrl }).save();
        }
        res.json({ success: true, imageUrl: fileUrl });
    } catch (err) { res.status(500).json({ success: false }); }
};

exports.serveSecureMedia = async (req, res) => {
    try {
        const filePath = path.join(__dirname, '../../uploads', req.params.filename);
        const MASTER_SECRET = process.env.MASTER_SECRET || 'GOGO_SECURE_ACCESS_2024_PROD';
        if (req.headers['x-gogo-secret'] !== MASTER_SECRET && req.query.token !== MASTER_SECRET) {
            return res.status(403).send("Unauthorized");
        }
        if (fs.existsSync(filePath)) res.sendFile(filePath);
        else res.status(404).send("Not found");
    } catch (e) { res.status(500).send("Error"); }
};

exports.markSeen = async (req, res) => {
    try {
        const m = normalize(req.body.myPhone), o = normalize(req.body.otherPhone);
        await Message.updateMany({ roomId: [m, o].sort().join('_'), receiverPhone: m, isOpened: false }, { isOpened: true, isDelivered: true });
        await resetUnreadCount(m, o);
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.updateMetadata = async (req, res) => {
    try {
        const { phone, partnerPhone, isMuted, isFavourite, isHidden } = req.body;
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
        const b1 = normalize(req.body.blockerPhone), b2 = normalize(req.body.blockedPhone);
        await Block.findOneAndUpdate({ blockerPhone: b1, blockedPhone: b2 }, { reason: req.body.reason, timestamp: new Date() }, { upsert: true });
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.unblockUser = async (req, res) => {
    try {
        const b1 = normalize(req.body.blockerPhone), b2 = normalize(req.body.blockedPhone);
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
        res.json({ success: true, photos: await RecentPhoto.find({ phone: normalize(req.params.phone) }).sort({ timestamp: -1 }).limit(20) });
    } catch (e) { res.status(500).json({ success: false }); }
};

exports.getBlockedList = async (req, res) => {
    try {
        const phone = normalize(req.params.phone);
        const blocks = await Block.find({ blockerPhone: phone }).lean();
        const partnerPhones = blocks.map(b => b.blockedPhone);

        const blockedUsers = await User.find({ phone: { $in: partnerPhones } }, 'phone name profileImages').lean();

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
            const filePath = path.join(process.cwd(), 'uploads', photo.imageUrl.split('/').pop());
            if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
            await RecentPhoto.findByIdAndDelete(req.params.messageId);
        }
        res.json({ success: true });
    } catch (e) { res.json({ success: true }); }
};

exports.deleteRecentPhotoByUrl = async (req, res) => {
    try {
        const phone = normalize(req.body.phone), url = req.body.imageUrl.split('?')[0];
        const photo = await RecentPhoto.findOne({ phone, imageUrl: url });
        if (photo) {
            const filePath = path.join(process.cwd(), 'uploads', url.split('/').pop());
            if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
            await RecentPhoto.deleteOne({ _id: photo._id });
        }
        res.json({ success: true });
    } catch (e) { res.status(500).json({ success: false }); }
};
