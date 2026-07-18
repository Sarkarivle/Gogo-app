const mongoose = require('mongoose');

const PolicySchema = new mongoose.Schema({
    type: { type: String, unique: true, required: true }, // e.g., 'privacy_policy', 'terms_conditions', 'refund_policy', 'about_us'
    url: { type: String, required: true },
    updatedAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('Policy', PolicySchema);
