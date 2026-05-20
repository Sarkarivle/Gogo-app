const Message = require('../models/Message');
const User = require('../models/User');
const Block = require('../models/Block');
const RecentPhoto = require('../models/RecentPhoto');
const path = require('path');
const fs = require('fs');

exports.getInbox = async (req, res) => {
    try {
        const phone = req.params.phone;
        const { page = 1, limit = 50 } = req.query;
        const skip = (parseInt(page) - 1) * parseInt(limit);

        const me = await User.findOne({ phone }, 'accountStatus');
        if (me && (me.accountStatus === 'Deactivated' || me.accountStatus === 'Suspended')) {
            return res.status(403).json({ success: false, message: "account deactivate" });
        }

        const blocks = await Block.find({ $or: [{ blockerPhone: phone }, { blockedPhone: phone }] });
        const blockedPhones = blocks.map(b => b.blockerPhone === phone ? b.blockedPhone : b.blockerPhone);

        // Find unique conversation partners using aggregation for efficiency
        const conversations = await Message.aggregate([
            {
                $match: {
                    $or: [{ senderPhone: phone }, { receiverPhone: phone }],
                    senderPhone: { $nin: blockedPhones },
                    receiverPhone: { $nin: blockedPhones }
                }
            },
            { $sort: { timestamp: -1 } },
            {
                $group: {
                    _id: {
                        $cond: [
                            { $eq: ["$senderPhone", phone] },
                            "$receiverPhone",
                            "$senderPhone"
                        ]
                    },
                    lastMsg: { $first: "$$ROOT" }
                }
            },
            { $sort: { "lastMsg.timestamp": -1 } },
            { $skip: skip },
            { $limit: parseInt(limit) }
        ]);

        const unreadCount = await Message.countDocuments({ receiverPhone: phone, isOpened: false });

        const partnerPhones = conversations.map(c => c._id);
        const partnerUsers = await User.find({ phone: { $in: partnerPhones } }, 'phone name lat lng position city area isOnline isVerified');
        const userMap = {};
        partnerUsers.forEach(u => userMap[u.phone] = u);

        const chats = await Promise.all(conversations.map(async (conv) => {
            const m = conv.lastMsg;
            const other = conv._id;
            const otherUser = userMap[other] || {};

            const partnerUnread = await Message.countDocuments({
                senderPhone: other,
                receiverPhone: phone,
                isOpened: false
            });

            return {
                phone: other,
                msg: m.type === 'audio' ? '🎵 Voice Message' : (m.message || (m.imageUrl ? '📷 Image' : '')),
                time: new Date(m.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                timestamp: m.timestamp,
                name: otherUser.name || 'User',
                pos: otherUser.position || 'Any',
                lat: otherUser.lat,
                lng: otherUser.lng,
                city: otherUser.city || 'Unknown',
                area: otherUser.area || '',
                unread: partnerUnread,
                isOnline: otherUser.isOnline || false,
                isVerified: otherUser.isVerified || false,
            };
        }));

        res.json({ totalUnread: unreadCount, chats });
    } catch (e) {
        console.error("GET_INBOX_ERROR:", e);
        res.status(500).json({ totalUnread: 0, chats: [] });
    }
};

exports.blockUser = async (req, res) => {
    try {
        const { blockerPhone, blockedPhone, reason, isReported } = req.body;
        await Block.findOneAndUpdate(
            { blockerPhone, blockedPhone },
            { reason, isReported, timestamp: new Date() },
            { upsert: true, new: true }
        );

        const roomId = [blockerPhone, blockedPhone].sort().join('_');
        const systemMsg = new Message({
            roomId,
            senderPhone: blockerPhone,
            receiverPhone: blockedPhone,
            message: `You blocked this user`,
            type: 'block_event'
        });
        await systemMsg.save();
        res.json({ success: true, message: "User blocked" });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.unblockUser = async (req, res) => {
    try {
        const { blockerPhone, blockedPhone } = req.body;
        await Block.findOneAndDelete({ blockerPhone, blockedPhone });

        const roomId = [blockerPhone, blockedPhone].sort().join('_');
        const systemMsg = new Message({
            roomId,
            senderPhone: blockerPhone,
            receiverPhone: blockedPhone,
            message: `Unblocked`,
            type: 'unblock_event'
        });
        await systemMsg.save();
        res.json({ success: true, message: "User unblocked" });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.checkBlock = async (req, res) => {
    try {
        const { p1, p2 } = req.params;
        const blockRecord = await Block.findOne({ blockerPhone: p1, blockedPhone: p2 });
        res.json({ success: true, isBlocked: !!blockRecord, blockerPhone: blockRecord ? blockRecord.blockerPhone : null });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.markSeen = async (req, res) => {
    try {
        const { myPhone, otherPhone } = req.body;
        const roomId = [myPhone, otherPhone].sort().join('_');
        await Message.updateMany(
            { roomId, receiverPhone: myPhone, isOpened: false },
            { isOpened: true, isDelivered: true }
        );
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.handleFileUpload = async (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ success: false, message: "Upload failed" });
        const fileUrl = `http://72.61.170.181:5000/uploads/${req.file.filename}`;
        const phone = req.body.phone;
        if (phone) {
            const newRecent = new RecentPhoto({ phone: phone, imageUrl: fileUrl });
            await newRecent.save();
        }
        res.json({ success: true, imageUrl: fileUrl });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
};

exports.getRecentPhotos = async (req, res) => {
    try {
        const { phone } = req.params;
        const photos = await RecentPhoto.find({ phone: phone }).sort({ timestamp: -1 }).limit(20);
        res.json({ success: true, photos });
    } catch (e) {
        res.status(500).json({ success: false, photos: [] });
    }
};

exports.deletePhoto = async (req, res) => {
    try {
        const { messageId } = req.params;
        const photo = await RecentPhoto.findById(messageId);
        if (!photo) return res.json({ success: true, message: "Not found" });
        const imageUrl = photo.imageUrl;
        await RecentPhoto.findByIdAndDelete(messageId);
        try {
            const fileName = imageUrl.split('/').pop();
            const filePath = path.join(process.cwd(), 'uploads', fileName);
            if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
        } catch (fErr) {}
        res.json({ success: true });
    } catch (e) {
        res.json({ success: true });
    }
};

exports.deleteRecentPhotoByUrl = async (req, res) => {
    try {
        const { phone, imageUrl } = req.body;
        const photo = await RecentPhoto.findOne({ phone, imageUrl });

        if (!photo) {
            return res.status(404).json({ success: false, message: "Photo not found in database" });
        }

        // 1. Delete from Database
        await RecentPhoto.deleteOne({ _id: photo._id });

        // 2. Delete from Server Storage
        try {
            const fileName = imageUrl.split('/').pop();
            const filePath = path.join(process.cwd(), 'uploads', fileName);
            if (fs.existsSync(filePath)) {
                fs.unlinkSync(filePath);
                console.log(`✅ File deleted: ${fileName}`);
            }
        } catch (fErr) {
            console.error("❌ File deletion error:", fErr);
        }

        res.json({ success: true, message: "Photo permanently deleted from server and database" });
    } catch (e) {
        console.error("DELETE_PHOTO_ERROR:", e);
        res.status(500).json({ success: false, error: e.message });
    }
};

exports.wipeRecentData = async (req, res) => {
    try {
        await RecentPhoto.deleteMany({});
        res.send("<h1>Recent Data Wiped Successfully</h1>");
    } catch (e) {
        res.status(500).send("Wipe failed: " + e.message);
    }
};
