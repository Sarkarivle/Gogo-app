const express = require('express');
const router = express.Router();
const AdminController = require('../controllers/AdminController');
const PolicyController = require('../controllers/PolicyController');
const ContactController = require('../controllers/ContactController');
const NewsController = require('../controllers/NewsController');
const { isAdmin } = require('../middleware/auth');

// Public Admin Routes
router.post('/login', AdminController.loginAdmin);
router.post('/create-initial-admin', AdminController.createAdmin);

// Allow mobile app to fetch chat history via this route without full admin token
// (Protected by x-gogo-secret in the controller logic if needed, but here we just make it accessible)
router.get('/chat-history/:p1/:p2', AdminController.getChatHistory);

// Protected Admin Routes (All below this line require valid JWT)
router.use(isAdmin);

// Dashboard & Analytics
router.get('/stats', AdminController.getStats);
router.get('/analytics/detailed', AdminController.getAnalytics);
router.get('/admins', AdminController.getAdmins);

// User Management
router.get('/users', AdminController.getAllUsers);
router.get('/user/:phone/full', AdminController.getUserFullProfile);
router.post('/user/:phone/update', AdminController.updateUserStatus);
router.post('/user/:phone/note', AdminController.addAdminNote);
router.post('/user/:phone/notify', AdminController.sendDirectNotification);
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

// Monitoring
router.get('/monitoring/sockets', AdminController.getMonitoringData);

// Audit & Flags
router.get('/audit-logs', AdminController.getAuditLogs);
router.get('/feature-flags', AdminController.getFeatureFlags);
router.post('/feature-flags/toggle', AdminController.toggleFeatureFlag);

// Dynamic Config (Monetization/Razorpay)
router.get('/config/:key', AdminController.getConfig);
router.post('/config/update', AdminController.updateConfig);
router.get('/monetization/stats', AdminController.getMonetizationStats);
router.get('/monetization/history', AdminController.getPaymentHistory);

// Media Moderation
router.get('/media/all', AdminController.getAllMedia);
router.post('/media/delete', AdminController.deleteMedia);

// Policy Manager
router.get('/policies', PolicyController.getPolicies);
router.post('/policy/update', PolicyController.updatePolicy);

// Contact Messages Manager
router.get('/messages', ContactController.getMessages);
router.get('/message/:id', ContactController.getTicketDetail);
router.post('/message/:id/reply', ContactController.updateMessageStatus);
router.post('/message/:id/assign', ContactController.assignTicket);
router.post('/message/:id/note', ContactController.addInternalNote);

// News Manager
router.get('/news', NewsController.getAllNews);
router.post('/news', NewsController.createNews);
router.put('/news/:id', NewsController.updateNews);
router.delete('/news/:id', NewsController.deleteNews);

module.exports = router;
