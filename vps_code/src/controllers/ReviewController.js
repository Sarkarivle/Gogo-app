const Review = require('../models/Review');

exports.submitReview = async (req, res) => {
    try {
        const { reviewerPhone, reviewerName, reviewedPhone, type, comment } = req.body;

        if (!reviewerPhone || !reviewedPhone) {
            return res.status(400).json({ success: false, message: 'Missing required fields' });
        }

        // Create or Update Review (Upsert style: one user can update their feedback for another)
        const review = await Review.findOneAndUpdate(
            { reviewerPhone, reviewedPhone },
            {
                reviewerName,
                type,
                comment,
                timestamp: new Date()
            },
            { upsert: true, new: true, setDefaultsOnInsert: true }
        );

        res.status(200).json({ success: true, review });
    } catch (error) {
        console.error('Submit Review Error:', error);
        res.status(500).json({ success: false, message: 'Internal server error' });
    }
};

exports.getReviews = async (req, res) => {
    try {
        const { phone } = req.params;

        if (!phone) {
            return res.status(400).json({ success: false, message: 'Phone number is required' });
        }

        const reviews = await Review.find({ reviewedPhone: phone })
            .sort({ timestamp: -1 })
            .limit(50); // Limit to last 50 reviews

        res.status(200).json({ success: true, reviews });
    } catch (error) {
        console.error('Get Reviews Error:', error);
        res.status(500).json({ success: false, message: 'Internal server error' });
    }
};
