const mongoose = require('mongoose');

const ConversationMetadataSchema = new mongoose.Schema({
    phone: { type: String, required: true, index: true },
    partnerPhone: { type: String, required: true, index: true },
    isMuted: { type: Boolean, default: false },
    isFavourite: { type: Boolean, default: false },
    isHidden: { type: Boolean, default: false }, // For "Delete From Chats"
    lastClearedAt: { type: Date, default: null }, // To hide messages older than this date for this user
}, { timestamps: true });

// Composite index for quick lookup
ConversationMetadataSchema.index({ phone: 1, partnerPhone: 1 }, { unique: true });

module.exports = mongoose.model('ConversationMetadata', ConversationMetadataSchema);
