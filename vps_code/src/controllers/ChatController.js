const Message = require('../models/Message');
const User = require('../models/User');
const Block = require('../models/Block');
const RecentPhoto = require('../models/RecentPhoto');
const ConversationMetadata = require('../models/ConversationMetadata');
const path = require('path');
const fs = require('fs');

exports.getInbox = async (req, res) => {
    try {
        const phone = req.params.phone;
        const { page = 1, limit = 50 } = req.query;
        const skip = (parseInt(page) - 1) * parseInt(limit);

        // Fetch all metadata for this user to apply filters (muted, hidden, favourites)
        const allMetadata = await ConversationMetadata.find({ phone });
        const metaMap = {};
        allMetadata.forEach(m => metaMap[m.partnerPhone] = m);

        // Find unique conversation partners using aggregation
        const conversations = await Message.aggregate([
            {
                $match: {
                    $or: [{ senderPhone: phone }, { receiverPhone: phone }]
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
            }
        ]);

        // Filter out hidden conversations (unless a newer message exists)
        const visibleConversations = conversations.filter(c => {
            const meta = metaMap[c._id];
            if (!meta) return true;
            if (meta.isHidden) {
                // Only keep if the last message is newer than when it was hidden/cleared
                return meta.lastClearedAt ? new Date(c.lastMsg.timestamp) > new Date(meta.lastClearedAt) : false;
            }
            return true;
        });

        const sortedVisible = visibleConversations.sort((a, b) => {
            // Priority 1: Latest message timestamp (Realtime Sort)
            const timeA = new Date(a.lastMsg.timestamp).getTime();
            const timeB = new Date(b.lastMsg.timestamp).getTime();

            if (timeB !== timeA) {
                return timeB - timeA;
            }

            // Priority 2: Unread messages (Optional fallback)
            // Since timestamps are high-precision, this is mostly a safeguard
            return 0;
        });

        const pagedConversations = sortedVisible.slice(skip, skip + parseInt(limit));

        const unreadCount = await Message.countDocuments({ receiverPhone: phone, isOpened: false });

        const partnerPhones = pagedConversations.map(c => c._id);
        const partnerUsers = await User.find({ phone: { $in: partnerPhones } }, 'phone name lat lng position city area isOnline isVerified');
        const userMap = {};
        partnerUsers.forEach(u => userMap[u.phone] = u);

        // Fetch block status for all partners
        const blocks = await Block.find({
            $or: [
                { blockerPhone: phone, blockedPhone: { $in: partnerPhones } },
                { blockerPhone: { $in: partnerPhones }, blockedPhone: phone }
            ]
        });

        const chats = await Promise.all(pagedConversations.map(async (conv) => {
            const m = conv.lastMsg;
            const other = conv._id;
            const otherUser = userMap[other] || {};
            const meta = metaMap[other] || {};

            const partnerUnread = await Message.countDocuments({
                senderPhone: other,
                receiverPhone: phone,
                isOpened: false
            });

            const blockInfo = blocks.find(b =>
                (b.blockerPhone === phone && b.blockedPhone === other) ||
                (b.blockerPhone === other && b.blockedPhone === phone)
            );

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
                isMuted: meta.isMuted || false,
                isFavourite: meta.isFavourite || false,
                isBlocked: !!blockInfo,
                iBlocked: blockInfo?.blockerPhone === phone
            };
        }));

        res.json({ totalUnread: unreadCount, chats });
    } catch (e) {
        console.error("GET_INBOX_ERROR:", e);
        res.status(500).json({ totalUnread: 0, chats: [] });
    }
};

exports.updateMetadata = async (req, res) => {
    try {
        const { phone, partnerPhone, isMuted, isFavourite, isHidden } = req.body;
        const update = {};
        if (isMuted !== undefined) update.isMuted = isMuted;
        if (isFavourite !== undefined) update.isFavourite = isFavourite;
        if (isHidden !== undefined) {
            update.isHidden = isHidden;
            if (isHidden) update.lastClearedAt = new Date();
        }

        const meta = await ConversationMetadata.findOneAndUpdate(
            { phone, partnerPhone },
            update,
            { upsert: true, new: true }
        );

        res.json({ success: true, meta });
    } catch (e) {
        res.status(500).json({ success: false });
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
        const blockRecord = await Block.findOne({
            $or: [
                { blockerPhone: p1, blockedPhone: p2 },
                { blockerPhone: p2, blockedPhone: p1 }
            ]
        });
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
        const roomId = [myPhone, otherPhone].sort().join('_');
        // IMPORTANT: We only mark regular messages as opened (seen).
        // View-once media must NOT be automatically marked as opened by markSeen.
        await Message.updateMany(
            { roomId, receiverPhone: myPhone, isOpened: false, isViewOnce: false },
            { isOpened: true, isDelivered: true }
        );
        res.json({ success: true });
    } catch (e) {
        res.status(500).json({ success: false });
    }
};

exports.handleFileUpload = async (req, res) => {
    try {
        console.log(`📂 Processing upload for phone: ${req.body.phone}`);
        if (!req.file) {
            console.error("❌ No file received in request");
            return res.status(400).json({ success: false, message: "No file received" });
        }

        console.log(`✅ File received: ${req.file.filename} (${req.file.size} bytes)`);

        // Build relative URL to ensure client can prepend its own baseUrl
        const fileUrl = `/api/media/${req.file.filename}`;

        const { phone, type } = req.body;
        if (phone) {
            try {
                // If app explicitly says it's an image or video, trust it and save to RecentPhoto
                if (type === 'image' || type === 'video') {
                    const newRecent = new RecentPhoto({ phone: phone, imageUrl: fileUrl });
                    await newRecent.save();
                    console.log(`📸 Saved to RecentPhoto: ${fileUrl} (App Type: ${type})`);
                } else {
                    console.log(`🚫 Skipped RecentPhoto: ${fileUrl} (App Type: ${type}) - Not a photo or video`);
                }
            } catch (saveErr) {
                console.error("⚠️ Error saving recent photo record:", saveErr);
            }
        }
        res.json({ success: true, imageUrl: fileUrl });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
};

exports.serveSecureMedia = async (req, res) => {
    try {
        const { filename } = req.params;
        const filePath = path.join(__dirname, '../../uploads', filename);

        // Professional Security Check
        const appSecret = req.headers['x-gogo-secret'];
        const urlToken = req.query.token;
        const MASTER_SECRET = 'GOGO_SECURE_ACCESS_2024_PROD';

        if (appSecret !== MASTER_SECRET && urlToken !== MASTER_SECRET) {
            return res.status(403).send("Unauthorized Access: This asset belongs to GoGo Private Infrastructure.");
        }

        if (fs.existsSync(filePath)) {
            res.sendFile(filePath);
        } else {
            res.status(404).send("Media not found");
        }
    } catch (e) {
        res.status(500).send("Server error");
    }
};

exports.getRecentPhotos = async (req, res) => {
    try {
        const { phone } = req.params;
        // Fetch all recent records for this user (filtering is already done during save)
        const photos = await RecentPhoto.find({ phone }).sort({ timestamp: -1 }).limit(20);
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
        let { phone, imageUrl } = req.body;

        // Clean URL: Strip token if present
        const cleanUrl = imageUrl.split('?')[0];

        // Find by either the tokenized version (unlikely in DB) or cleaned version
        const photo = await RecentPhoto.findOne({
            phone,
            $or: [{ imageUrl: cleanUrl }, { imageUrl: imageUrl }]
        });

        if (!photo) {
            return res.status(404).json({ success: false, message: "Photo not found in database" });
        }

        // 1. Delete from Database
        await RecentPhoto.deleteOne({ _id: photo._id });

        // 2. Delete from Server Storage
        try {
            // Ensure we extract only the actual filename without any query params
            const fileName = cleanUrl.split('/').pop();
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
