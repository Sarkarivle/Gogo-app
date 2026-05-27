const mongoose = require('mongoose');

const ReportSchema = new mongoose.Schema({
    reporterPhone: { type: String, required: true },
    reportedPhone: { type: String, required: true },
    category: { type: String, required: true },
    reportType: {
        type: String,
        enum: ['Profile Report', 'Chat Report', 'Report & Block'],
        default: 'Profile Report'
    },
    description: String,
    status: { type: String, enum: ['Pending', 'Reviewed', 'Action Taken'], default: 'Pending', index: true },
    adminNote: String,
    timestamp: { type: Date, default: Date.now }
}, { timestamps: true });

module.exports = mongoose.model('Report', ReportSchema);
