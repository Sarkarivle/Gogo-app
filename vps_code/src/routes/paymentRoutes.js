const express = require('express');
const router = express.Router();
const PaymentController = require('../controllers/PaymentController');
const { isUser, isAdmin } = require('../middleware/auth');

router.post('/create-order', isUser, PaymentController.createOrder);
router.post('/verify-payment', isUser, PaymentController.verifyPayment);
router.post('/cancel', isUser, PaymentController.cancelSubscription);
router.get('/sync-status', isUser, PaymentController.syncUserStatus);
router.post('/broadcast-status-change', isAdmin, PaymentController.notifyStatusChange);
router.get('/settings', PaymentController.getPublicSettings);

// Webhooks
router.post('/webhook/razorpay', PaymentController.handleRazorpayWebhook);
router.post('/webhook/phonepe', PaymentController.handlePhonePeWebhook);
router.post('/webhook/cashfree', PaymentController.handleCashfreeWebhook);

// Backward compatibility
router.post('/webhook', PaymentController.handleRazorpayWebhook);

module.exports = router;
