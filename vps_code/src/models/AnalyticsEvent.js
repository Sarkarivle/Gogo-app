const mongoose = require('mongoose');

const AnalyticsEventSchema = new mongoose.Schema({
    type: { type: String, required: true, index: true },
    distinctId: { type: String, required: true, index: true }, // phone, deviceId, or socketId
    metadata: { type: Object },
    timestamp: { type: Date, default: Date.now, index: true }
}, { timestamps: true });

// Ensure we can easily count unique distinctIds per type per day
AnalyticsEventSchema.index({ type: 1, distinctId: 1, timestamp: -1 });

module.exports = mongoose.model('AnalyticsEvent', AnalyticsEventSchema);
