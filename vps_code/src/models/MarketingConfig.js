const mongoose = require('mongoose');

const MarketingConfigSchema = new mongoose.Schema({
    key: { type: String, required: true, unique: true }, // e.g., 'global_settings'
    fbPixelId: { type: String, default: '' },
    googleAdsId: { type: String, default: '' },
    tiktokPixelId: { type: String, default: '' },

    // S2S Postback URLs (TrafficStar, etc.)
    installPostbackUrl: { type: String, default: '' },
    registrationPostbackUrl: { type: String, default: '' },
    purchasePostbackUrl: { type: String, default: '' },

    // Toggles
    isTrackingEnabled: { type: Boolean, default: true },
    logUserIp: { type: Boolean, default: false },

    lastUpdatedBy: { type: String, default: 'admin' }
}, { timestamps: true });

module.exports = mongoose.model('MarketingConfig', MarketingConfigSchema);
