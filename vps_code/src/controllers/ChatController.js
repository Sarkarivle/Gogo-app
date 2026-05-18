const Message = require('../models/Message');
const User = require('../models/User');
const Block = require('../models/Block');

exports.getInbox = async (req, res) => {
    try {
        const phone = req.params.phone;

        // Check if requester is deactivated
        const me = await User.findOne({ phone }, 'accountStatus');
        if (me && (me.accountStatus === 'Deactivated' || me.accountStatus === 'Suspended')) {
            return res.status(403).json({ success: false, message: "account deactivate" });
        }

        // Get blocked list
        const blocks = await Block.find({ $or: [{ blockerPhone: phone }, { blockedPhone: phone }] });
        const blockedPhones = blocks.map(b => b.blockerPhone === phone ? b.blockedPhone : b.blockerPhone);

        const messages = await Message.find({
            $or: [{ senderPhone: phone }, { receiverPhone: phone }],
            senderPhone: { $nin: blockedPhones },
            receiverPhone: { $nin: blockedPhones }
        }).sort({ timestamp: -1 });

        // Count total unread for this user
        const unreadCount = await Message.countDocuments({ receiverPhone: phone, seen: false });

        let partners = {};

        // Fetch all users details
        const allUsers = await User.find({}, 'phone name lat lng position city area isOnline isVerified');
        const userMap = {};
        allUsers.forEach(u => userMap[u.phone] = u);

        for (const m of messages) {
            let other = m.senderPhone === phone ? m.receiverPhone : m.senderPhone;
            if (!partners[other]) {
                const otherUser = userMap[other] || {};

                const partnerUnread = await Message.countDocuments({
                    senderPhone: other,
                    receiverPhone: phone,
                    seen: false
                });

                partners[other] = {
                    phone: other,
                    msg: m.type === 'audio' ? '🎵 Voice Message' : (m.message || (m.imageUrl ? '📷 Image' : '')),
                    time: new Date(m.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                    name: otherUser.name || 'User',
                    pos: otherUser.position || 'Any',
                    lat: otherUser.lat,
                    lng: otherUser.lng,
                    city: otherUser.city || 'Unknown',
                    area: otherUser.area || '',
                    unread: partnerUnread,
                    isOnline: otherUser.isOnline || false,
                    isVerified: otherUser.isVerified || false,
                    dist: 'Unknown'
                };
            }
        }
        res.json({ totalUnread: unreadCount, chats: Object.values(partners) });
    } catch (e) {
        res.status(500).json({ totalUnread: 0, chats: [] });
    }
};

exports.blockUser = async (req, res) => {
    try {
        const { blockerPhone, blockedPhone, reason, isReported } = req.body;

        // 1. Save Block Record
        await Block.findOneAndUpdate(
            { blockerPhone, blockedPhone },
            { reason, isReported, timestamp: new Date() },
            { upsert: true, new: true }
        );

        // 2. Create System Message in Chat for Permanent Record
        const roomId = [blockerPhone, blockedPhone].sort().join('_');
        const systemMsg = new Message({
            roomId,
            senderPhone: blockerPhone,
            receiverPhone: blockedPhone,
            message: `You blocked this user`,
            type: 'block_event'
        });
        await systemMsg.save();

        res.json({ success: true, message: "User blocked", systemMsg });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.unblockUser = async (req, res) => {
    try {
        const { blockerPhone, blockedPhone } = req.body;

        // 1. Remove Block Record
        await Block.findOneAndDelete({ blockerPhone, blockedPhone });

        // 2. Create System Message for Record
        const roomId = [blockerPhone, blockedPhone].sort().join('_');
        const systemMsg = new Message({
            roomId,
            senderPhone: blockerPhone,
            receiverPhone: blockedPhone,
            message: `Unblocked`,
            type: 'unblock_event'
        });
        await systemMsg.save();

        res.json({ success: true, message: "User unblocked", systemMsg });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.checkBlock = async (req, res) => {
    try {
        const { p1, p2 } = req.params;
        // Check specifically if p1 blocked p2
        const blockRecord = await Block.findOne({ blockerPhone: p1, blockedPhone: p2 });

        res.json({
            success: true,
            isBlocked: !!blockRecord,
            blockerPhone: blockRecord ? blockRecord.blockerPhone : null
        });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.markSeen = async (req, res) => {
    try {
        const { myPhone, otherPhone } = req.body;
        await Message.updateMany(
            { senderPhone: otherPhone, receiverPhone: myPhone, seen: false },
            { seen: true }
        );
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.handleFileUpload = (req, res) => {
    if (!req.file) return res.status(400).json({ success: false, message: "Upload failed" });
    const fileUrl = `http://72.61.170.181:5000/uploads/${req.file.filename}`;
    res.json({ success: true, imageUrl: fileUrl });
};

exports.getRecentPhotos = async (req, res) => {
    try {
        const { phone } = req.params;
        const photos = await Message.find({
            senderPhone: phone,
            type: 'image',
            imageUrl: { $exists: true, $ne: null }
        }).sort({ timestamp: -1 }).limit(20);

        res.json({ success: true, photos });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.deletePhoto = async (req, res) => {
    try {
        const { messageId } = req.params;
        const msg = await Message.findById(messageId);
        if (msg && msg.imageUrl) {
            const fileName = msg.imageUrl.split('/').pop();
            const filePath = path.join(__dirname, '../../uploads', fileName);
            if (fs.existsSync(filePath)) {
                fs.unlinkSync(filePath);
            }
        }
        await Message.findByIdAndDelete(messageId);
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};
