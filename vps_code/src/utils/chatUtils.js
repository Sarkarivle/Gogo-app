const Conversation = require('../models/Conversation');

/**
 * Updates or creates a conversation entry for both participants (Optimized)
 */
async function updateConversationSummary(message) {
    try {
        const msg = message.toObject ? message.toObject() : message;
        let { senderPhone, receiverPhone, message: text, type, timestamp, imageUrl, audioUrl, isDeletedForEveryone } = msg;

        if (!senderPhone || !receiverPhone) return;

        senderPhone = String(senderPhone).replace(/[^0-9]/g, '');
        receiverPhone = String(receiverPhone).replace(/[^0-9]/g, '');

        let displayMessage = text;
        if (isDeletedForEveryone) {
            displayMessage = "This message was deleted";
        } else if (!displayMessage) {
            if (type === 'image') displayMessage = '📷 Image';
            else if (type === 'audio') displayMessage = '🎵 Voice Message';
            else if (type === 'video') displayMessage = '🎥 Video';
        }

        const summary = {
            message: displayMessage,
            type: type || 'text',
            timestamp: timestamp || new Date(),
            senderPhone,
            imageUrl: isDeletedForEveryone ? null : imageUrl,
            audioUrl: isDeletedForEveryone ? null : audioUrl,
            isDeletedForEveryone: isDeletedForEveryone || false
        };

        // Run updates in parallel for better performance
        await Promise.all([
            Conversation.findOneAndUpdate(
                { userPhone: senderPhone, partnerPhone: receiverPhone },
                { $set: { lastMessage: summary } },
                { upsert: true }
            ),
            Conversation.findOneAndUpdate(
                { userPhone: receiverPhone, partnerPhone: senderPhone },
                {
                    $set: { lastMessage: summary },
                    $inc: { unreadCount: (type === 'block_event' || type === 'unblock_event') ? 0 : 1 }
                },
                { upsert: true, new: true }
            ).then(updatedConv => {
                // Emit unread update to receiver's sockets for realtime inbox badge
                if (updatedConv && (type !== 'block_event' && type !== 'unblock_event')) {
                    const io = require('../services/analyticsService').io; // Access global io
                    if (io) {
                        io.to(`user_${receiverPhone}`).emit('unread_update', {
                            phone: senderPhone,
                            unreadCount: updatedConv.unreadCount,
                            lastMessage: summary
                        });
                    }
                }
            })
        ]);
    } catch (e) {
        // Silent error in production
    }
}

async function resetUnreadCount(userPhone, partnerPhone) {
    try {
        const uPhone = String(userPhone).replace(/[^0-9]/g, '');
        const pPhone = String(partnerPhone).replace(/[^0-9]/g, '');
        await Conversation.findOneAndUpdate(
            { userPhone: uPhone, partnerPhone: pPhone },
            { $set: { unreadCount: 0 } }
        );
    } catch (e) {}
}

module.exports = { updateConversationSummary, resetUnreadCount };
