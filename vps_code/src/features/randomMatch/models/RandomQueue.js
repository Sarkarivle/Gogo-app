const mongoose = require('mongoose');

const RandomQueueSchema = new mongoose.Schema({
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    phone: { type: String, required: true, unique: true },
    socketId: { type: String, required: true },
    status: { type: String, enum: ['waiting', 'matched'], default: 'waiting' },
    gender: { type: String },
    country: { type: String },
    callType: { type: String, default: 'random_video' },
    joinedAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('RandomQueue', RandomQueueSchema);
