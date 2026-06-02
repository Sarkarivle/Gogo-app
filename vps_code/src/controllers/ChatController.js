const Message = require('../models/Message');
const User = require('../models/User');
const Block = require('../models/Block');
const RecentPhoto = require('../models/RecentPhoto');
const ConversationMetadata = require('../models/ConversationMetadata');
const Conversation = require('../models/Conversation');
const { updateConversationSummary, resetUnreadCount } = require('../utils/chatUtils');
const { normalize, phoneQuery } = require('../utils/phoneUtils');
const path = require('path');
const fs = require('fs');
const jwt = require('jsonwebtoken');

/**
 * Helper to calculate distance for privacy
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
    try {
        const p1Lat = parseFloat(lat1);
        const p1Lon = parseFloat(lon1);
        const p2Lat = parseFloat(lat2);
        const p2Lon = parseFloat(lon2);

        if (isNaN(p1Lat) || isNaN(p1Lon) || isNaN(p2Lat) || isNaN(p2Lon)) return "";

        const R = 6371;
        const dLat = (p2Lat - p1Lat) * Math.PI / 180;
        const dLon = (p2Lon - p1Lon) * Math.PI / 180;
        const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                  Math.cos(p1Lat * Math.PI / 180) * Math.cos(p2Lat * Math.PI / 180) *
                  Math.sin(dLon / 2) * Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        const d = R * c;

        if (d < 0.5) return "0.5 km";
        if (d < 1) return "Within 1 km";
        if (d < 5) return "Under 5 km";
        return d.toFixed(1) + " km";
    } catch (e) {
        return "";
    }
}

exports.getInbox = async (req, res) => {
    try {
        let phone = normalize(req.params.phone);
        // IDOR Prevention: Always prefer token phone for users
        if (req.user && !req.user.role) phone = normalize(req.user.phone);

        const page = Math.max(1, parseInt(req.query.page || 1));
        const limit = Math.max(1, parseInt(req.query.limit || 50));
        const skip = (page - 1) * limit;

        // Optimized Search: Always use normalized 10-digit phone
        // We still check variations for backward compatibility if needed, but prefer normalized
        const phoneVariations = [phone, `+91${phone}`, `91${phone}`];

        // Fetch current user for distance calculation
        const caller = await User.findOne({ phone: { $in: phoneVariations } }, 'lat lng location').lean();
        const userLat = caller?.lat || caller?.location?.coordinates?.[1];
        const userLng = caller?.lng || caller?.location?.coordinates?.[0];

        // 1. Fetch conversations
        const [conversations, allMetadata] = await Promise.all([
            Conversation.find({ userPhone: { $in: phoneVariations } })
                .sort({ 'lastMessage.timestamp': -1 })
                .skip(skip)
                .limit(limit)
                .lean(),
            ConversationMetadata.find({ phone: { $in: phoneVariations } }).lean()
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
            User.find({ phone: { $in: partnerPhones } }, 'phone name isOnline isVerified city area position lat lng location').lean(),
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
            const meta = metaMap[other] || {};

            const cleanArea = (u.area && u.area.toLowerCase() !== 'unknown') ? u.area : '';
            const cleanCity = (u.city && u.city.toLowerCase() !== 'unknown') ? u.city : '';

            const uLat = u.lat || u.location?.coordinates?.[1];
            const uLng = u.lng || u.location?.coordinates?.[0];
            const distStr = (userLat && userLng && uLat && uLng) ? calculateDistance(userLat, userLng, uLat, uLng) : "";

            return {
                phone: other,
                msg: conv.lastMessage?.message || '',
                type: conv.lastMessage?.type || 'text',
                timestamp: conv.lastMessage?.timestamp || new Date(),
                name: u.name || 'User',
                unread: conv.unreadCount || 0,
                isOnline: u.isOnline || false,
                isVerified: u.isVerified || false,
                isBlocked: !!block,
                iBlocked: block?.blockerPhone === phone,
                city: cleanArea || cleanCity || 'Nearby',
                distance: distStr,
                position: u.position || '',
                isFavourite: meta.isFavourite || false,
                isMuted: meta.isMuted || false
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

        // Match 10-digit roomId (Fastest) or variations (Legacy)
        const roomId = [p1, p2].sort().join('_');
        const roomIdPart1 = p1 + '_' + p2;
        const roomIdPart2 = p2 + '_' + p1;

        const [chats, block, partner] = await Promise.all([
            Message.find({
                $or: [
                    { roomId: roomId },
                    { roomId: { $in: [roomIdPart1, roomIdPart2, `+91${roomIdPart1}`, `+91${roomIdPart2}`] } }
                ],
                deletedBy: { $ne: p1 }
            })
                .sort({ timestamp: -1 })
                .skip((parseInt(page) - 1) * parseInt(limit))
                .limit(parseInt(limit)),
            Block.findOne({ $or: [{ blockerPhone: p1, blockedPhone: p2 }, { blockerPhone: p2, blockedPhone: p1 }] }),
            User.findOne({ phone: p2 }, 'isDeactivated accountStatus')
        ]);

        const messages = chats.reverse();
        const isBlocked = !!block;
        const blockerPhone = block ? block.blockerPhone : null;
        const isPartnerDeactivated = partner ? (partner.isDeactivated || partner.accountStatus === 'Deactivated') : false;

        if (parseInt(page) === 1) {
            res.json({
                messages,
                isBlocked,
                blockerPhone,
                isPartnerDeactivated
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

        const filePath = path.join(__dirname, '../../uploads', filename);
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

        if (fs.existsSync(filePath)) res.sendFile(filePath);
        else res.status(404).send("Not found");
    } catch (e) { res.status(500).send("Error"); }
};

exports.markSeen = async (req, res) => {
    try {
        let m = req.body.myPhone;
        // Security: Ensure user can only mark their own chats as seen
        if (req.user && !req.user.role) m = req.user.phone;

        m = normalize(m);
        const o = normalize(req.body.otherPhone);
        const phoneVariations = [m, `+91${m}`, `91${m}`];

        // SECURITY FIX: Only mark normal messages as 'Opened' (Seen).
        // 'View Once' messages MUST NOT be marked as opened automatically.
        await Message.updateMany({
            $or: [
                { roomId: [m, o].sort().join('_') },
                { roomId: [`+91${m}`, `+91${o}`].sort().join('_') }
            ],
            receiverPhone: { $in: phoneVariations },
            isOpened: false,
            isViewOnce: false
        }, { isOpened: true, isDelivered: true });

        // For View Once, just ensure they are marked as Delivered but NOT opened.
        await Message.updateMany({
            $or: [
                { roomId: [m, o].sort().join('_') },
                { roomId: [`+91${m}`, `+91${o}`].sort().join('_') }
            ],
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

        const blocks = await Block.find({ blockerPhone: new RegExp(phone + '$') }).lean();
        const partnerPhones = blocks.map(b => b.blockedPhone);

        const blockedUsers = await User.find({ phone: { $in: partnerPhones.map(p => new RegExp(normalize(p) + '$')) } }, 'phone name profileImages').lean();

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
