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
    },
    unreadCount: { type: Number, default: 0 }
}, { timestamps: true });

// Ensure unique conversation entry per user-partner pair
ConversationSchema.index({ userPhone: 1, partnerPhone: 1 }, { unique: true });

module.exports = mongoose.model('Conversation', ConversationSchema);
