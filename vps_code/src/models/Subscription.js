const mongoose = require('mongoose');

const SubscriptionSchema = new mongoose.Schema({
    userPhone: { type: String, required: true, unique: true, index: true },
    planName: { type: String, default: 'Pro' },
    status: { type: String, enum: ['Active', 'Cancelled', 'Expired'], default: 'Active' },
    expiryDate: { type: Date },
    cancelledAt: Date,
    price: Number
}, { timestamps: true });

module.exports = mongoose.model('Subscription', SubscriptionSchema);
