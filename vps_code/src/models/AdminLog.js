const mongoose = require('mongoose');

const AdminLogSchema = new mongoose.Schema({
    adminId: String,
    action: String, // e.g., "Ban User", "Delete Message"
    target: String, // e.g., Phone number of target
    details: String,
    timestamp: { type: Date, default: Date.now }
});

module.exports = mongoose.model('AdminLog', AdminLogSchema);
