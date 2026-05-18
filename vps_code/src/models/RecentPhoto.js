const mongoose = require('mongoose');

const RecentPhotoSchema = new mongoose.Schema({
    phone: { type: String, required: true },
    imageUrl: { type: String, required: true },
    timestamp: { type: Date, default: Date.now }
});

module.exports = mongoose.model('RecentPhoto', RecentPhotoSchema);
