const mongoose = require('mongoose');

const CampaignSchema = new mongoose.Schema({
    title: { type: String },
    message: { type: String, required: true },
    targetAudience: [{ type: String }], // 'premium', 'free', 'unregistered'
    totalSent: { type: Number, default: 0 },
    totalFailed: { type: Number, default: 0 }, // FCM Failures (Likely Uninstalls)
    totalDelivered: { type: Number, default: 0 },
    status: { type: String, enum: ['Scheduled', 'Sending', 'Sent', 'Failed'], default: 'Sent' },
    scheduledAt: { type: Date },
    executedAt: { type: Date, default: Date.now }
}, { timestamps: true });

module.exports = mongoose.model('Campaign', CampaignSchema);
