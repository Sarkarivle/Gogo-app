const mongoose = require('mongoose');

const BlockSchema = new mongoose.Schema({
    blockerPhone: { type: String, required: true, index: true },
    blockedPhone: { type: String, required: true, index: true },
    reason: { type: String, default: 'Manual Block' },
    isReported: { type: Boolean, default: false },
    timestamp: { type: Date, default: Date.now }
}, { timestamps: true });

// Compound index to quickly check if a pair is blocked
BlockSchema.index({ blockerPhone: 1, blockedPhone: 1 }, { unique: true });

module.exports = mongoose.model('Block', BlockSchema);
