const mongoose = require('mongoose');

const InternalNoteSchema = new mongoose.Schema({
    note: { type: String, required: true },
    adminName: String,
    adminId: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
    timestamp: { type: Date, default: Date.now }
});

const ContactMessageSchema = new mongoose.Schema({
    // User Info
    name: String,
    phone: String,
    email: String,
    userPhone: String, // Linking to actual user account if available

    // Ticket Details
    subject: String,
    message: { type: String, required: true },
    category: {
        type: String,
        enum: [
            'Payment Issue', 'Premium Subscription', 'Login Problem',
            'OTP Issue', 'Report User', 'Child Safety', 'Harassment',
            'Technical Bug', 'Account Ban', 'Verification Issue', 'Other'
        ],
        default: 'Other'
    },
    priority: {
        type: String,
        enum: ['Low', 'Medium', 'High', 'Critical'],
        default: 'Medium'
    },
    status: {
        type: String,
        enum: ['Pending', 'In Review', 'Waiting For User', 'Escalated', 'Resolved', 'Closed', 'Reopened'],
        default: 'Pending'
    },

    // Assignment
    assignedTo: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
    assignedToName: String,
    assignedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
    assignedAt: Date,

    // Communication
    adminReply: String,
    internalNotes: [InternalNoteSchema],
    attachments: [String], // URLs to screenshots/evidence

    // Realtime & Meta
    isLive: { type: Boolean, default: false },
    lastAdminActivity: Date,
    lastUserActivity: Date,

    // Audit & SLA
    resolvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin' },
    resolvedAt: Date,
    responseStartAt: Date, // When admin first opened/replied
    responseTimeMs: Number, // First response time
    resolutionTimeMs: Number, // Total time to resolve

    // User Context Snapshot
    userContext: {
        userId: String,
        premiumStatus: Boolean,
        deviceInfo: String,
        signupDate: Date,
        reportCount: Number,
        activityScore: Number
    }
}, { timestamps: true });

// Auto-escalation for specific categories
ContactMessageSchema.pre('save', function(next) {
    if (this.isNew) {
        if (['Child Safety', 'Harassment', 'Payment Issue'].includes(this.category)) {
            this.priority = this.category === 'Child Safety' ? 'Critical' : 'High';
        }
    }
    next();
});

module.exports = mongoose.model('ContactMessage', ContactMessageSchema);
