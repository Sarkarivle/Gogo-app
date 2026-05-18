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
const upload = multer({ storage: storage });

router.get('/inbox/:phone', ChatController.getInbox);
router.get('/check-block/:p1/:p2', ChatController.checkBlock);
router.post('/block', ChatController.blockUser);
router.post('/unblock', ChatController.unblockUser);
router.post('/mark-seen', ChatController.markSeen);
router.post('/upload', upload.single('image'), ChatController.handleFileUpload);
router.get('/recent-photos/:phone', ChatController.getRecentPhotos);
router.delete('/photo/:messageId', ChatController.deletePhoto);

module.exports = router;
