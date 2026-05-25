const Conversation = require('../models/Conversation');

/**
 * Updates or creates a conversation entry for both participants
 */
async function updateConversationSummary(message) {
    try {
        // Handle both Mongoose documents and plain objects
        const msg = message.toObject ? message.toObject() : message;
        const { senderPhone, receiverPhone, message: text, type, timestamp, imageUrl, audioUrl } = msg;

        if (!senderPhone || !receiverPhone) return;

        const summary = {
            message: text || (type === 'image' ? '📷 Image' : (type === 'audio' ? '🎵 Voice Message' : '')),
            type: type || 'text',
            timestamp: timestamp || new Date(),
            senderPhone,
            imageUrl,
            audioUrl
        };

        // Update for Sender
        await Conversation.findOneAndUpdate(
            { userPhone: senderPhone, partnerPhone: receiverPhone },
            {
                $set: { lastMessage: summary },
                // We don't increment unread for sender
            },
            { upsert: true }
        );

        // Update for Receiver
        await Conversation.findOneAndUpdate(
            { userPhone: receiverPhone, partnerPhone: senderPhone },
            {
                $set: { lastMessage: summary },
                $inc: { unreadCount: type === 'block_event' || type === 'unblock_event' ? 0 : 1 }
            },
            { upsert: true }
        );
    } catch (e) {
        console.error("Error updating conversation summary:", e);
    }
}

/**
 * Reset unread count for a user in a specific conversation
 */
async function resetUnreadCount(userPhone, partnerPhone) {
    try {
        await Conversation.findOneAndUpdate(
            { userPhone, partnerPhone },
            { $set: { unreadCount: 0 } }
        );
    } catch (e) {
        console.error("Error resetting unread count:", e);
    }
}

module.exports = {
    updateConversationSummary,
    resetUnreadCount
};
