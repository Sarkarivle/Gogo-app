const express = require('express');
const router = express.Router();
const PaymentController = require('../controllers/PaymentController');
const auth = require('../middleware/auth');

const isUser = auth.isUser;
const isAdmin = auth.isAdmin;

router.post('/create-order', isUser, PaymentController.createOrder);
router.post('/verify-payment', isUser, PaymentController.verifyPayment);
router.post('/cancel', isUser, PaymentController.cancelSubscription);
router.get('/sync-status', isUser, PaymentController.syncUserStatus);
router.post('/broadcast-status-change', isAdmin, PaymentController.broadcastStatusChange);
router.get('/settings', PaymentController.getPublicSettings);

// Webhooks
router.post('/webhook/razorpay', PaymentController.handleRazorpayWebhook);
router.post('/webhook/phonepe', PaymentController.handlePhonePeWebhook);
router.post('/webhook/cashfree', PaymentController.handleCashfreeWebhook);

// Backward compatibility
router.post('/webhook', PaymentController.handleRazorpayWebhook);

module.exports = router;
