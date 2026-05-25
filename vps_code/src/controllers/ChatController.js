const Message = require('../models/Message');
const User = require('../models/User');
const Block = require('../models/Block');
const RecentPhoto = require('../models/RecentPhoto');
const ConversationMetadata = require('../models/ConversationMetadata');
const Conversation = require('../models/Conversation');
const { updateConversationSummary, resetUnreadCount } = require('../utils/chatUtils');
const path = require('path');
const fs = require('fs');

/**
 * Helper to calculate distance for privacy
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
    const p1Lat = parseFloat(lat1);
    const p1Lon = parseFloat(lon1);
    const p2Lat = parseFloat(lat2);
    const p2Lon = parseFloat(lon2);

    // Check if any coordinate is missing or essentially zero
    if (!p1Lat || !p1Lon || !p2Lat || !p2Lon) return "";

    const R = 6371; // km
    const dLat = (p2Lat - p1Lat) * Math.PI / 180;
    const dLon = (p2Lon - p1Lon) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(p1Lat * Math.PI / 180) * Math.cos(p2Lat * Math.PI / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const d = R * c;

    // Estimated distance labels for privacy
    if (d < 1) return "Within 1 km";
    return `${d.toFixed(1)} km`;
}

exports.getInbox = async (req, res) => {
    try {
        const phone = req.params.phone;
        const { page = 1, limit = 50 } = req.query;
        const skip = (parseInt(page) - 1) * parseInt(limit);

        const currentUser = await User.findOne({ phone }, 'lat lng location');

        const allMetadata = await ConversationMetadata.find({ phone });
        const metaMap = {};
        allMetadata.forEach(m => metaMap[m.partnerPhone] = m);

        // Fetch optimized conversations
        const conversations = await Conversation.find({ userPhone: phone }).lean();

        // If inbox is empty, it might be because migration hasn't run.
        // We'll return success with empty array, but the developer should run /api/chat/migrate-inbox once.

        // Filter and Safety Check
        const visibleConversations = conversations.filter(c => {
            if (!c.lastMessage) return false; // Skip if no message content

            const meta = metaMap[c.partnerPhone];
            if (!meta) return true;
            if (meta.isHidden) {
                const lastMsgTime = new Date(c.lastMessage.timestamp || 0).getTime();
                const clearedAtTime = new Date(meta.lastClearedAt || 0).getTime();
                return lastMsgTime > clearedAtTime;
            }
            return true;
        });

        const sortedVisible = visibleConversations.sort((a, b) => {
            const timeA = new Date(a.lastMessage?.timestamp || 0).getTime();
            const timeB = new Date(b.lastMessage?.timestamp || 0).getTime();
            return timeB - timeA;
        });

        const pagedConversations = sortedVisible.slice(skip, skip + parseInt(limit));
        const totalUnreadCount = visibleConversations.reduce((sum, c) => sum + (c.unreadCount || 0), 0);

        const partnerPhones = pagedConversations.map(c => c.partnerPhone);
        const partnerUsers = await User.find({ phone: { $in: partnerPhones } }, 'phone name lat lng location position city area isOnline isVerified');
        const userMap = {};
        partnerUsers.forEach(u => userMap[u.phone] = u);

        const blocks = await Block.find({
            $or: [
                { blockerPhone: phone, blockedPhone: { $in: partnerPhones } },
                { blockerPhone: { $in: partnerPhones }, blockedPhone: phone }
            ]
        });

        const chats = pagedConversations.map((conv) => {
            const m = conv.lastMessage || {};
            const other = conv.partnerPhone;
            const otherUser = userMap[other] || {};
            const meta = metaMap[other] || {};

            const blockInfo = blocks.find(b =>
                (b.blockerPhone === phone && b.blockedPhone === other) ||
                (b.blockerPhone === other && b.blockedPhone === phone)
            );

            // Smart Location Fallback
            const myLat = currentUser?.lat || (currentUser?.location?.coordinates ? currentUser.location.coordinates[1] : null);
            const myLng = currentUser?.lng || (currentUser?.location?.coordinates ? currentUser.location.coordinates[0] : null);
            const otherLat = otherUser.lat || (otherUser.location?.coordinates ? otherUser.location.coordinates[1] : null);
            const otherLng = otherUser.lng || (otherUser.location?.coordinates ? otherUser.location.coordinates[0] : null);

            const distLabel = calculateDistance(myLat, myLng, otherLat, otherLng);

            // Clean Area/City from "Unknown" strings
            const cleanArea = (otherUser.area && otherUser.area.toLowerCase() !== 'unknown') ? otherUser.area : '';
            const cleanCity = (otherUser.city && otherUser.city.toLowerCase() !== 'unknown') ? otherUser.city : '';

            // Priority: Area/Village > City > Nearby
            const locationLabel = cleanArea || cleanCity || "Nearby";

            return {
                phone: other,
                msg: m.type === 'audio' ? '🎵 Voice Message' : (m.message || (m.imageUrl ? '📷 Image' : '')),
                time: m.timestamp ? new Date(m.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '',
                timestamp: m.timestamp || new Date(),
                name: otherUser.name || 'User',
                pos: otherUser.position || 'Any',
                distance: distLabel,
                city: locationLabel,
                area: '',
                unread: conv.unreadCount || 0,
                isOnline: otherUser.isOnline || false,
                isVerified: otherUser.isVerified || false,
                isMuted: meta.isMuted || false,
                isFavourite: meta.isFavourite || false,
                isBlocked: !!blockInfo,
                iBlocked: blockInfo?.blockerPhone === phone
            };
        });

        res.json({ totalUnread: totalUnreadCount, chats });
    } catch (e) {
        console.error("GET_INBOX_ERROR:", e);
        res.status(500).json({ totalUnread: 0, chats: [], error: e.message });
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
        await updateConversationSummary(systemMsg);
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
        await updateConversationSummary(systemMsg);
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
        await Message.updateMany(
            { roomId, receiverPhone: myPhone, isOpened: false, isViewOnce: false },
            { isOpened: true, isDelivered: true }
        );
        await resetUnreadCount(myPhone, otherPhone);
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
            if (fs.existsSync(filePath)) await fs.promises.unlink(filePath);
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
                await fs.promises.unlink(filePath);
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
        console.error("GET_CHAT_HISTORY_ERROR:", e);
        res.status(500).json([]);
    }
};
