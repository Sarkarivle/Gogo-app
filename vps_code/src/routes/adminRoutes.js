const express = require('express');
const router = express.Router();
const AdminController = require('../controllers/AdminController');
const PolicyController = require('../controllers/PolicyController');
const ContactController = require('../controllers/ContactController');

// Dashboard & Analytics
router.get('/stats', AdminController.getStats);
router.get('/analytics/detailed', AdminController.getAnalytics);

// User Management
router.get('/users', AdminController.getAllUsers);
router.get('/user/:phone/full', AdminController.getUserFullProfile);
router.post('/user/:phone/update', AdminController.updateUserStatus);
router.delete('/user/:phone/clear-chat', AdminController.clearUserChat);
router.delete('/user/:phone/delete-account', AdminController.deleteUser);

// Reports
router.get('/reports', AdminController.getReports);
router.post('/reports/handle', AdminController.handleReport);

// Verification
router.get('/verification/requests', AdminController.getVerificationRequests);
router.post('/verification/approve/:phone', AdminController.approveVerification);

// Engagement
router.post('/broadcast', AdminController.broadcastNotification);

// Chat & Inbox
router.get('/inbox/:phone', AdminController.getUserInboxes);
router.get('/chat-history/:p1/:p2', AdminController.getChatHistory);

// Monitoring
router.get('/monitoring/sockets', AdminController.getMonitoringData);

// Audit & Flags
router.get('/audit-logs', AdminController.getAuditLogs);
router.get('/feature-flags', AdminController.getFeatureFlags);
router.post('/feature-flags/toggle', AdminController.toggleFeatureFlag);

// Dynamic Config (Monetization/Razorpay)
router.get('/config/:key', AdminController.getConfig);
router.post('/config/update', AdminController.updateConfig);

// Policy Manager
router.get('/policies', PolicyController.getPolicies);
router.post('/policy/update', PolicyController.updatePolicy);

// Contact Messages Manager
router.get('/messages', ContactController.getMessages);
router.post('/message/:id/reply', ContactController.updateMessageStatus);

module.exports = router;
