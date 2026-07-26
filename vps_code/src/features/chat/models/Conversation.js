const mongoose = require('mongoose');

const ConversationSchema = new mongoose.Schema({
    userPhone: { type: String, required: true, index: true },
    partnerPhone: { type: String, required: true, index: true },
    lastMessage: {
        message: String,
        type: { type: String },
        timestamp: { type: Date },
        senderPhone: String,
        imageUrl: String,
        audioUrl: String,
        isDeletedForEveryone: { type: Boolean, default: false }
    },
    unreadCount: { type: Number, default: 0 }
}, { timestamps: true });

// Ensure unique conversation entry per user-partner pair
ConversationSchema.index({ userPhone: 1, partnerPhone: 1 }, { unique: true });
ConversationSchema.index({ userPhone: 1, 'lastMessage.timestamp': -1 });

module.exports = mongoose.model('Conversation', ConversationSchema);
