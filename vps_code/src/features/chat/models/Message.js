const mongoose = require('mongoose');

const MessageSchema = new mongoose.Schema({
    roomId: { type: String, index: true },
    senderPhone: { type: String, index: true },
    receiverPhone: { type: String, index: true },
    localId: String, // Added for deduplication and client-side mapping
    message: String,
    imageUrl: String,
    audioUrl: String,
    type: { type: String, enum: ['text', 'image', 'video', 'audio', 'block_event', 'unblock_event', 'call_log'], default: 'text' },
    isViewOnce: { type: Boolean, default: false },
    isOpened: { type: Boolean, default: false },
    isDelivered: { type: Boolean, default: false },
    isEdited: { type: Boolean, default: false },
    editedAt: Date,
    isDeletedForEveryone: { type: Boolean, default: false },
    deletedAt: Date,
    deletedBy: { type: [String], default: [] },

    metadata: mongoose.Schema.Types.Mixed,

    // Reply context
    replyToId: { type: mongoose.Schema.Types.ObjectId, ref: 'Message' },
    replyText: String,
    replyType: String,

    timestamp: { type: Date, default: Date.now }
}, { timestamps: true });

// Index for pagination and fast retrieval
MessageSchema.index({ roomId: 1, timestamp: -1 });
MessageSchema.index({ receiverPhone: 1, isDelivered: 1 });
MessageSchema.index({ roomId: 1, receiverPhone: 1, isOpened: 1 });

module.exports = mongoose.model('Message', MessageSchema);
