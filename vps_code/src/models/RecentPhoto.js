const mongoose = require('mongoose');

const RecentPhotoSchema = new mongoose.Schema({
    phone: { type: String, required: true, index: true },
    imageUrl: { type: String, required: true },
    timestamp: { type: Date, default: Date.now }
});

RecentPhotoSchema.index({ phone: 1, timestamp: -1 });

module.exports = mongoose.model('RecentPhoto', RecentPhotoSchema);
