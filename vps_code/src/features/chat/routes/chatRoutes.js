const express = require('express');
const router = express.Router();
const ChatController = require('../controllers/ChatController');
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
        cb(null, Date.now() + path.extname(file.originalname));
    }
});
const upload = multer({
    storage: storage,
    limits: { fileSize: 50 * 1024 * 1024 }, // Limit: 50MB
    fileFilter: (req, file, cb) => {
        const fileLog = `📝 [FILE_FILTER] Name: ${file.originalname}, MIME: ${file.mimetype}`;
        console.log(fileLog);

        // Very permissive regex to avoid blocking valid mobile media
        const allowedPattern = /image|audio|video|jpeg|jpg|png|gif|webp|heic|heif|mp3|wav|m4a|ogg|aac|amr|3gp|mp4|webm|quicktime|octet-stream/i;

        const isExtAllowed = allowedPattern.test(path.extname(file.originalname));
        const isMimeAllowed = allowedPattern.test(file.mimetype);

        if (isExtAllowed || isMimeAllowed) {
            return cb(null, true);
        }

        console.error(`❌ [FILE_REJECTED] ${fileLog}`);
        cb(new Error(`Error: File type not supported! (${file.originalname} / ${file.mimetype})`));
    }
});

const { isUser } = require('../../../shared/middleware/auth');

router.use(isUser);

router.get('/inbox/:phone', ChatController.getInbox);
router.get('/blocked-list/:phone', ChatController.getBlockedList);
router.get('/history/:p1/:p2', ChatController.getChatHistory); // Added for mobile app access
router.get('/check-block/:p1/:p2', ChatController.checkBlock);
router.post('/block', ChatController.blockUser);
router.post('/unblock', ChatController.unblockUser);
router.post('/mark-seen', ChatController.markSeen);
router.post('/update-metadata', ChatController.updateMetadata);
router.post('/upload', upload.single('image'), ChatController.handleFileUpload);
router.get('/recent-photos/:phone', ChatController.getRecentPhotos);
router.post('/delete-recent-photo', ChatController.deleteRecentPhotoByUrl);
router.delete('/photo/:messageId', ChatController.deletePhoto);
router.post('/call/check-credit', ChatController.checkCallCredit);

module.exports = router;
