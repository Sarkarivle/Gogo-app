const express = require('express');
const router = express.Router();
const UserController = require('../controllers/UserController');
const ContactController = require('../controllers/ContactController');
const PolicyController = require('../controllers/PolicyController');

router.post('/login', UserController.login);
router.post('/register', UserController.register);
router.post('/update-location', UserController.updateLocation);
router.post('/update-profile', UserController.updateProfile);
router.post('/update-premium', UserController.updatePremium);
router.post('/report', UserController.reportUser);
router.post('/update-fcm', UserController.updateFcmToken);
router.post('/verify-request', UserController.submitVerification);

// Contact & Policies
router.post('/contact-us', ContactController.submitMessage);
router.get('/policy/:type', PolicyController.getPolicyByType);
router.get('/policies', PolicyController.getPolicies);

module.exports = router;
