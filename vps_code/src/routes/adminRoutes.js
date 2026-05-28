const express = require('express');
const router = express.Router();
const AdminController = require('../controllers/AdminController');
const PolicyController = require('../controllers/PolicyController');
const ContactController = require('../controllers/ContactController');
const NewsController = require('../controllers/NewsController');
const MarketingController = require('../controllers/MarketingController');
const { isAdmin } = require('../middleware/auth');

// Safety function to prevent "Undefined" crash
const s = (fn) => fn || ((req, res) => res.status(500).json({ error: "Not Implemented" }));

router.post('/login', s(AdminController.loginAdmin));
router.post('/create-initial-admin', s(AdminController.createAdmin));
router.get('/chat-history/:p1/:p2', s(AdminController.getChatHistory));

router.use(isAdmin);

router.get('/stats', s(AdminController.getStats));
router.get('/analytics/detailed', s(AdminController.getAnalytics));
router.get('/admins', s(AdminController.getAdmins));
router.get('/users', s(AdminController.getAllUsers));
router.get('/user/:phone/full', s(AdminController.getUserFullProfile));
router.post('/user/:phone/update', s(AdminController.updateUserStatus));
router.post('/user/:phone/note', s(AdminController.addAdminNote));
router.post('/user/:phone/notify', s(AdminController.sendDirectNotification));
router.delete('/user/:phone/clear-chat', s(AdminController.clearUserChat));
router.delete('/user/:phone/delete-account', s(AdminController.deleteUser));
router.get('/reports', s(AdminController.getReports));
router.post('/reports/handle', s(AdminController.handleReport));
router.get('/verification/requests', s(AdminController.getVerificationRequests));
router.post('/verification/approve/:phone', s(AdminController.approveVerification));
router.post('/broadcast', s(AdminController.broadcastNotification));
router.get('/inbox/:phone', s(AdminController.getUserInboxes));
router.get('/monitoring/sockets', s(AdminController.getMonitoringData));
router.get('/audit-logs', s(AdminController.getAuditLogs));
router.get('/feature-flags', s(AdminController.getFeatureFlags));
router.post('/feature-flags/toggle', s(AdminController.toggleFeatureFlag));
router.get('/config/:key', s(AdminController.getConfig));
router.post('/config/update', s(AdminController.updateConfig));
router.get('/monetization/stats', s(AdminController.getMonetizationStats));
router.get('/monetization/history', s(AdminController.getPaymentHistory));
router.get('/media/all', s(AdminController.getAllMedia));
router.post('/media/delete', s(AdminController.deleteMedia));

// Marketing Config
router.get('/marketing/config', s(MarketingController.getConfig));
router.post('/marketing/config', s(MarketingController.updateConfig));

// External Controllers
router.get('/policies', s(PolicyController.getPolicies));
router.post('/policy/update', s(PolicyController.updatePolicy));
router.get('/messages', s(ContactController.getMessages));
router.get('/message/:id', s(ContactController.getTicketDetail));
router.post('/message/:id/reply', s(ContactController.updateMessageStatus));
router.post('/message/:id/assign', s(ContactController.assignTicket));
router.post('/message/:id/note', s(ContactController.addInternalNote));
router.get('/news', s(NewsController.getAllNews));
router.post('/news', s(NewsController.createNews));
router.put('/news/:id', s(NewsController.updateNews));
router.delete('/news/:id', s(NewsController.deleteNews));

module.exports = router;
