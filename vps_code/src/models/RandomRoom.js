const mongoose = require('mongoose');

const RandomRoomSchema = new mongoose.Schema({
    roomId: { type: String, required: true, unique: true, index: true },
    hostId: { type: String, required: true },
    guestId: { type: String, default: null },
    status: {
        type: String,
        enum: ['waiting', 'connecting', 'connected', 'closing', 'expired'],
        default: 'waiting'
    },
    socketIds: {
        host: { type: String, required: true },
        guest: { type: String, default: null }
    },
    rtcConnected: { type: Boolean, default: false },
    expiresAt: { type: Date, default: () => new Date(Date.now() + 5 * 60 * 1000) }
}, { timestamps: true });

RandomRoomSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
RandomRoomSchema.index({ hostId: 1 });
RandomRoomSchema.index({ guestId: 1 });
RandomRoomSchema.index({ status: 1 });

module.exports = mongoose.model('RandomRoom', RandomRoomSchema);
