const mongoose = require('mongoose');

const ReviewSchema = new mongoose.Schema({
    reviewerPhone: { type: String, required: true, index: true },
    reviewerName: { type: String, required: true },
    reviewedPhone: { type: String, required: true, index: true },
    type: { type: String, enum: ['good', 'bad'], default: 'good' },
    comment: { type: String, default: '' },
    timestamp: { type: Date, default: Date.now }
}, { timestamps: true });

// Ensure a user can only review another user once (optional, but good practice)
// ReviewSchema.index({ reviewerPhone: 1, reviewedPhone: 1 }, { unique: true });

module.exports = mongoose.model('Review', ReviewSchema);
