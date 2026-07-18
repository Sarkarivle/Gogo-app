const mongoose = require('mongoose');

const VerificationRequestSchema = new mongoose.Schema({
    userPhone: { type: String, required: true, unique: true },
    selfieUrl: String, // User upload for verification
    status: { type: String, enum: ['Pending', 'Approved', 'Rejected'], default: 'Pending' },
    submittedAt: { type: Date, default: Date.now },
    reviewedAt: Date,
    adminId: String
});

module.exports = mongoose.model('VerificationRequest', VerificationRequestSchema);
