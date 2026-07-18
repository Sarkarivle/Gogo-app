const express = require('express');
const router = express.Router();
const reviewController = require('../controllers/ReviewController');

router.post('/submit', reviewController.submitReview);
router.get('/list/:phone', reviewController.getReviews);

module.exports = router;
