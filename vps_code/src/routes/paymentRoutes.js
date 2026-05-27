const express = require('express');
const router = express.Router();
const PaymentController = require('../controllers/PaymentController');
const { isUser } = require('../middleware/auth');

router.post('/create-order', isUser, PaymentController.createOrder);
router.post('/verify-payment', isUser, PaymentController.verifyPayment);
router.get('/settings', PaymentController.getPublicSettings);

// Webhooks
router.post('/webhook/razorpay', PaymentController.handleRazorpayWebhook);
router.post('/webhook/phonepe', PaymentController.handlePhonePeWebhook);
router.post('/webhook/cashfree', PaymentController.handleCashfreeWebhook);

// Backward compatibility
router.post('/webhook', PaymentController.handleRazorpayWebhook);

module.exports = router;
