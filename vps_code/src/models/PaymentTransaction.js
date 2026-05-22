const mongoose = require('mongoose');

const PaymentTransactionSchema = new mongoose.Schema({
    orderId: { type: String, required: true, unique: true, index: true },
    userPhone: { type: String, required: true, index: true },
    gateway: { type: String, required: true, enum: ['razorpay', 'phonepe', 'cashfree'] },
    amount: { type: Number, required: true },
    currency: { type: String, default: 'INR' },
    status: { type: String, enum: ['PENDING', 'SUCCESS', 'FAILED', 'CANCELLED'], default: 'PENDING' },
    gatewayTransactionId: String,
    gatewaySubscriptionId: String,
    gatewayCustomerId: String,
    paymentMethod: String,
    errorMessage: String,
    webhookLogs: [mongoose.Schema.Types.Mixed],
    metadata: mongoose.Schema.Types.Mixed
}, { timestamps: true });

module.exports = mongoose.model('PaymentTransaction', PaymentTransactionSchema);
