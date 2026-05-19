const mongoose = require('mongoose');

const MessageSchema = new mongoose.Schema({
    roomId: { type: String, index: true },
    senderPhone: { type: String, index: true },
    receiverPhone: { type: String, index: true },
    message: String,
    imageUrl: String,
    audioUrl: String,
    type: { type: String, enum: ['text', 'image', 'video', 'audio', 'block_event', 'unblock_event'], default: 'text' },
    isViewOnce: { type: Boolean, default: false },
    isOpened: { type: Boolean, default: false },
    isDelivered: { type: Boolean, default: false },
    isEdited: { type: Boolean, default: false },
    isDeletedForEveryone: { type: Boolean, default: false },

    // Reply context
    replyToId: { type: mongoose.Schema.Types.ObjectId, ref: 'Message' },
    replyText: String,
    replyType: String,

    timestamp: { type: Date, default: Date.now }
}, { timestamps: true });

// Index for pagination and fast retrieval
MessageSchema.index({ roomId: 1, timestamp: -1 });

module.exports = mongoose.model('Message', MessageSchema);
