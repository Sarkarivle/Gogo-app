const express = require('express');
const router = express.Router();
const AdminController = require('../controllers/AdminController');
const PolicyController = require('../../policy/controllers/PolicyController');
const ContactController = require('../../contact/controllers/ContactController');
const NewsController = require('../../news/controllers/NewsController');
const MarketingController = require('../../marketing/controllers/MarketingController');
const { isAdmin } = require('../../../shared/middleware/auth');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dir = './uploads';
        if (!fs.existsSync(dir)) fs.mkdirSync(dir);
        cb(null, dir);
    },
    filename: (req, file, cb) => {
        cb(null, 'login_image_' + Date.now() + path.extname(file.originalname));
    }
});
const upload = multer({ storage });

const creatorStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dir = './uploads';
        if (!fs.existsSync(dir)) fs.mkdirSync(dir);
        cb(null, dir);
    },
    filename: (req, file, cb) => {
        cb(null, 'creator_' + Date.now() + path.extname(file.originalname));
    }
});
const uploadCreatorPhoto = multer({ storage: creatorStorage });

const greetingAudioStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dir = path.join(process.cwd(), 'public', 'audio', 'greetings');
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        cb(null, dir);
    },
    filename: (req, file, cb) => {
        cb(null, 'greeting_' + Date.now() + path.extname(file.originalname));
    }
});
const uploadGreetingAudio = multer({
    storage: greetingAudioStorage,
    limits: { fileSize: 10 * 1024 * 1024 }, // 10MB — these are short voice clips
    fileFilter: (req, file, cb) => {
        const allowed = /mp3|m4a|wav|aac|ogg|mpeg/i;
        if (allowed.test(path.extname(file.originalname)) || allowed.test(file.mimetype)) return cb(null, true);
        cb(new Error('Only audio files (mp3, m4a, wav, aac, ogg) are allowed'));
    }
});

const randomLiveVideoStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dir = path.join(process.cwd(), 'public', 'video', 'randomlive');
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        cb(null, dir);
    },
    filename: (req, file, cb) => {
        cb(null, 'randomlive_' + Date.now() + path.extname(file.originalname));
    }
});
const uploadRandomLiveVideo = multer({
    storage: randomLiveVideoStorage,
    limits: { fileSize: 80 * 1024 * 1024 }, // 80MB — short video clips
    fileFilter: (req, file, cb) => {
        const allowed = /mp4|mov|webm|quicktime|m4v/i;
        if (allowed.test(path.extname(file.originalname)) || allowed.test(file.mimetype)) return cb(null, true);
        cb(new Error('Only video files (mp4, mov, webm) are allowed'));
    }
});

// Safety function to prevent "Undefined" crash
const s = (fn) => fn || ((req, res) => res.status(500).json({ error: "Not Implemented" }));

router.post('/login', s(AdminController.loginAdmin));
router.post('/create-initial-admin', s(AdminController.createAdmin));
router.get('/chat-history/:p1/:p2', s(AdminController.getChatHistory));

router.use(isAdmin);

router.get('/stats', s(AdminController.getStats));
router.get('/analytics/detailed', s(AdminController.getAnalytics));
router.get('/admins', s(AdminController.getAdmins));
router.put('/admin/:id', s(AdminController.updateAdmin));
router.delete('/admin/:id', s(AdminController.deleteAdmin));
router.get('/users', s(AdminController.getAllUsers));
router.get('/creators', s(AdminController.getCreators));
router.post('/creators', uploadCreatorPhoto.single('photo'), s(AdminController.createCreator));
router.delete('/creators/:id', s(AdminController.deleteCreator));
router.get('/creators/greeting-audio', s(AdminController.getGreetingAudioClips));
router.post('/creators/greeting-audio', uploadGreetingAudio.single('audio'), s(AdminController.uploadGreetingAudioClip));
router.delete('/creators/greeting-audio/:filename', s(AdminController.deleteGreetingAudioClip));
router.get('/creators/random-live-videos', s(AdminController.getRandomLiveVideos));
router.post('/creators/random-live-videos', uploadRandomLiveVideo.single('video'), s(AdminController.uploadRandomLiveVideo));
router.delete('/creators/random-live-videos/:filename', s(AdminController.deleteRandomLiveVideo));
router.get('/user/:phone/full', s(AdminController.getUserFullProfile));
router.get('/user/:phone/timeline', s(AdminController.getUserTimeline));
router.post('/user/:phone/update', s(AdminController.updateUserStatus));
router.post('/user/:phone/note', s(AdminController.addAdminNote));
router.post('/user/:phone/notify', s(AdminController.sendDirectNotification));
router.delete('/user/:phone/clear-chat', s(AdminController.clearUserChat));
router.delete('/user/:phone/delete-account', s(AdminController.deleteUser));
router.post('/users/bulk-delete', s(AdminController.bulkDeleteUsers));
router.get('/reports', s(AdminController.getReports));
router.post('/reports/handle', s(AdminController.handleReport));
router.post('/report/status', s(AdminController.handleReport)); // Alias for compatibility
router.get('/verification/requests', s(AdminController.getVerificationRequests));
router.post('/verification/approve/:phone', s(AdminController.approveVerification));
router.post('/verification/reject/:phone', s(AdminController.rejectVerification));
router.post('/broadcast', s(AdminController.broadcastNotification));
router.get('/campaigns', s(AdminController.getCampaigns));
router.get('/inbox/:phone', s(AdminController.getUserInboxes));
router.get('/monitoring/sockets', s(AdminController.getMonitoringData));
router.get('/audit-logs', s(AdminController.getAuditLogs));
router.get('/feature-flags', s(AdminController.getFeatureFlags));
router.post('/feature-flags/toggle', s(AdminController.toggleFeatureFlag));
router.get('/config/:key', s(AdminController.getConfig));
router.post('/config/update', s(AdminController.updateConfig));
router.get('/monetization/stats', s(AdminController.getMonetizationStats));
router.get('/monetization/history', s(AdminController.getPaymentHistory));
router.get('/monetization/google-play-dashboard', s(AdminController.getGooglePlayFullDashboard));
router.get('/media/all', s(AdminController.getAllMedia));
router.post('/media/delete', s(AdminController.deleteMedia));

// Marketing Config
router.get('/marketing/config', s(MarketingController.getConfig));
router.post('/marketing/config', s(MarketingController.updateConfig));
router.post('/marketing/upload-login-image', upload.single('login_image'), s(MarketingController.uploadLoginImage));

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
