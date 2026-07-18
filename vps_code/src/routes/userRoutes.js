const express = require('express');
const router = express.Router();
const UserController = require('../controllers/UserController');
const ContactController = require('../controllers/ContactController');
const PolicyController = require('../controllers/PolicyController');
const NewsController = require('../controllers/NewsController');
const MarketingController = require('../controllers/MarketingController');
const { isUser } = require('../middleware/auth');

router.post('/login', UserController.login);
router.post('/register', UserController.register);

// Protected Routes
router.get('/profile/:phone', isUser, UserController.getProfile);
router.post('/update-location', isUser, UserController.updateLocation);
router.post('/update-profile', isUser, UserController.updateProfile);
router.post('/update-premium', isUser, UserController.updatePremium);
router.post('/report', isUser, UserController.reportUser);
router.post('/update-fcm', isUser, UserController.updateFcmToken);
router.post('/verify-request', isUser, UserController.submitVerification);
router.get('/discover', isUser, UserController.getDiscover);
router.post('/track-event', UserController.trackEvent); // Unprotected for login analytics
router.post('/deactivate', isUser, UserController.deactivateAccount);
router.post('/reactivate', isUser, UserController.reactivateAccount);
router.post('/mark-trial-used', isUser, UserController.markTrialUsed);

// Contact & Policies
router.post('/contact-us', ContactController.submitMessage);
router.get('/policy/:type', PolicyController.getPolicyByType);
router.get('/policies', PolicyController.getPolicies);

// News
router.get('/news/public', NewsController.getPublicNews);

// Public Config
router.get('/config/:key', UserController.getPublicConfig);

// Tracking Config
router.get('/tracking-config', MarketingController.getAppTrackingConfig);

module.exports = router;
