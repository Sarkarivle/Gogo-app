const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
    // Core Identity
    phone: { type: String, unique: true, required: true, index: true },
    name: { type: String, index: 'text' },
    gender: { type: String, enum: ['Male', 'Female', 'Other'], default: 'Male' },
    age: Number,
    dobDay: String, dobMonth: String, dobYear: String,

    // Profile Content
    bio: String,
    position: String,
    havePlace: String,
    heightFt: String, heightInch: String, weight: String,
    profileImages: [{ type: String }], // Array for multiple images

    // Location
    lat: { type: Number, index: '2dsphere' }, // Geolocation index
    lng: { type: Number },
    city: { type: String, index: true },
    area: String,
    lastLocationUpdate: { type: Date, default: Date.now },

    // Status & Moderation
    isPremium: { type: Boolean, default: false },
    premiumExpiry: { type: Date },
    premiumPlan: { type: String }, // e.g., 'Monthly', 'Yearly'
    isVerified: { type: Boolean, default: false }, // Blue tick status

    // Payment Tracking
    paymentHistory: [{
        orderId: String,
        paymentId: String,
        amount: Number,
        currency: String,
        status: String,
        plan: String,
        timestamp: { type: Date, default: Date.now }
    }],
    accountStatus: {
        type: String,
        enum: ['Active', 'Deactivated', 'Suspended', 'Banned'],
        default: 'Active'
    },
    isBanned: { type: Boolean, default: false },
    banReason: String,
    isOnline: { type: Boolean, default: false },
    lastSeen: { type: Date, default: Date.now },
    hasCompletedOnboarding: { type: Boolean, default: false },

    // Security & Tracking
    ipAddress: String,
    deviceId: String,
    fcmToken: String, // For Push Notifications

    // Timestamps
    createdAt: { type: Date, default: Date.now }
}, { timestamps: true });

// Index for search
UserSchema.index({ name: 'text', phone: 'text', city: 'text' });

module.exports = mongoose.model('User', UserSchema);
