const mongoose = require('mongoose');

const ContactMessageSchema = new mongoose.Schema({
    name: String,
    phone: String,
    email: String,
    subject: String,
    message: { type: String, required: true },
    status: { type: String, enum: ['Pending', 'Resolved'], default: 'Pending' },
    adminReply: String,
    createdAt: { type: Date, default: Date.now }
}, { timestamps: true });

module.exports = mongoose.model('ContactMessage', ContactMessageSchema);
