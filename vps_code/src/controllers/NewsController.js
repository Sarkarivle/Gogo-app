const NewsArticle = require('../models/NewsArticle');

exports.getAllNews = async (req, res) => {
    try {
        const news = await NewsArticle.find().sort({ sort_order: 1, published_at: -1 });
        res.json({ success: true, data: news });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.getPublicNews = async (req, res) => {
    try {
        const { page = 1, limit = 10 } = req.query;
        const news = await NewsArticle.find({ is_active: true })
            .sort({ sort_order: 1, published_at: -1 })
            .limit(limit * 1)
            .skip((page - 1) * limit);

        const count = await NewsArticle.countDocuments({ is_active: true });

        res.json({
            success: true,
            data: news,
            totalPages: Math.ceil(count / limit),
            currentPage: page
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.createNews = async (req, res) => {
    try {
        const news = new NewsArticle(req.body);
        await news.save();
        res.json({ success: true, data: news });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.updateNews = async (req, res) => {
    try {
        const news = await NewsArticle.findByIdAndUpdate(req.params.id, req.body, { new: true });
        res.json({ success: true, data: news });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

exports.deleteNews = async (req, res) => {
    try {
        await NewsArticle.findByIdAndDelete(req.params.id);
        res.json({ success: true, message: 'News deleted successfully' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};
