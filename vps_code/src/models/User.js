const mongoose = require('mongoose');

const UserSchema = new mongoose.Schema({
    // Core Identity
    phone: { type: String, unique: true, required: true, index: true },
    name: { type: String, index: 'text' },
    gender: { type: String, enum: ['Male', 'Female', 'Other'], default: 'Male', index: true },
    age: Number,
    dobDay: String, dobMonth: String, dobYear: String,

    // Profile Content
    bio: String,
    position: String,
    havePlace: String,
    heightFt: String, heightInch: String, weight: String,
    profileImages: [{ type: String }], // Array for multiple images

    // Location
    lat: { type: Number },
    lng: { type: Number },
    location: {
        type: { type: String, enum: ['Point'], default: 'Point' },
        coordinates: { type: [Number], default: [0, 0] } // [lng, lat]
    },
    city: { type: String, index: true },
    area: String,
    lastLocationUpdate: { type: Date, default: Date.now },

    // Status & Moderation
    isPremium: { type: Boolean, default: false, index: true },
    premiumExpiry: { type: Date },
    premiumPlan: { type: String }, // e.g., 'Monthly Gold'
    isVerified: { type: Boolean, default: false }, // Blue tick status
    isShadowBanned: { type: Boolean, default: false }, // Shadow ban status
    monetizationMode: { type: String, enum: ['payer', 'adDriven'], default: 'payer' },
    adminNotes: [{
        note: String,
        adminName: String,
        timestamp: { type: Date, default: Date.now }
    }],

    // Advanced Subscription Management
    subscription: {
        id: { type: String, index: true }, // Razorpay Subscription ID
        customerId: String,
        planId: String,
        status: {
            type: String,
            enum: ['none', 'trial_active', 'active', 'payment_failed', 'cancelled', 'expired'],
            default: 'none'
        },
        trialStartDate: Date,
        trialEndDate: Date,
        startDate: Date,
        nextBillingDate: Date,
        totalAmountPaid: { type: Number, default: 0 },
        lastAmountPaid: { type: Number, default: 0 },
        autoRenew: { type: Boolean, default: true },
        cancellationDate: Date,
        lastPaymentDate: Date,
        paymentMethod: String,
        hasUsedTrial: { type: Boolean, default: false },
    },

    // Payment Tracking
    paymentHistory: [{
        orderId: String,
        paymentId: String,
        amount: Number,
        currency: { type: String, default: 'INR' },
        status: String, // e.g., 'Captured', 'Failed', 'Refunded'
        method: String,
        timestamp: { type: Date, default: Date.now }
    }],
    accountStatus: {
        type: String,
        enum: ['Active', 'Deactivated', 'Suspended', 'Banned'],
        default: 'Active'
    },
    isBanned: { type: Boolean, default: false },
    banReason: String,
    isDeactivated: { type: Boolean, default: false },
    deactivatedAt: { type: Date },
    reactivatedAt: { type: Date },
    deactivationReason: String,
    lastPremiumSnapshot: {
        isPremium: Boolean,
        premiumExpiry: Date,
        premiumPlan: String,
        subscriptionStatus: String
    },
    isOnline: { type: Boolean, default: false, index: true },
    lastSeen: { type: Date, default: Date.now, index: true },
    chatCount: { type: Number, default: 0, index: true },
    hasCompletedOnboarding: { type: Boolean, default: false },

    // Security & Tracking
    ipAddress: String,
    deviceId: String,
    fcmToken: String, // For Push Notifications
    deviceHistory: [{
        deviceId: String,
        model: String,
        os: String,
        ip: String,
        lastUsed: { type: Date, default: Date.now }
    }],

    // Timestamps
    createdAt: { type: Date, default: Date.now }
}, { timestamps: true });

// Index for search
UserSchema.index({ location: '2dsphere' });
UserSchema.index({ name: 'text', phone: 'text', city: 'text' });
UserSchema.index({ createdAt: -1 });
UserSchema.index({ isBanned: 1, isDeactivated: 1 });
UserSchema.index({ isPremium: -1, lastSeen: -1 });
UserSchema.index({ accountStatus: 1, lastSeen: -1 }); // Fast Discovery
UserSchema.index({ isOnline: 1, lastSeen: -1 }); // Fast Online Tab
UserSchema.index({ isPremium: -1, isVerified: -1, isOnline: -1, lastSeen: -1 }); // Optimized Discovery
UserSchema.index({ chatCount: -1, lastSeen: -1 }); // Fast Popular Tab

module.exports = mongoose.model('User', UserSchema);
