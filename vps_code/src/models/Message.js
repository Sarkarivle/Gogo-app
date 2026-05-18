const mongoose = require('mongoose');

const MessageSchema = new mongoose.Schema({
    roomId: String,
    senderPhone: String,
    receiverPhone: String,
    message: String,
    imageUrl: String,
    audioUrl: String,
    type: { type: String, enum: ['text', 'image', 'video', 'audio', 'block_event', 'unblock_event'], default: 'text' },
    isViewOnce: { type: Boolean, default: false },
    isOpened: { type: Boolean, default: false },
    seen: { type: Boolean, default: false },
    timestamp: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Message', MessageSchema);
