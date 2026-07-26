const mongoose = require('mongoose');

const FeatureFlagSchema = new mongoose.Schema({
    name: { type: String, required: true, unique: true },
    key: { type: String, required: true, unique: true },
    isEnabled: { type: Boolean, default: false },
    description: { type: String },
    updatedBy: { type: String },
    updatedAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('FeatureFlag', FeatureFlagSchema);
