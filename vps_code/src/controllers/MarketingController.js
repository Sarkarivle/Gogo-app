const MarketingConfig = require('../models/MarketingConfig');

exports.getConfig = async (req, res) => {
    try {
        let config = await MarketingConfig.findOne({ key: 'global_settings' });
        if (!config) {
            config = new MarketingConfig({ key: 'global_settings' });
            await config.save();
        }
        res.json({ success: true, config });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

exports.updateConfig = async (req, res) => {
    try {
        const updateData = req.body;
        const config = await MarketingConfig.findOneAndUpdate(
            { key: 'global_settings' },
            { $set: updateData },
            { new: true, upsert: true }
        );
        res.json({ success: true, config, message: "Marketing config updated!" });
    } catch (err) {
        res.status(500).json({ success: false, message: err.message });
    }
};

// Public route for the App to fetch tracking IDs
exports.getAppTrackingConfig = async (req, res) => {
    try {
        const config = await MarketingConfig.findOne({ key: 'global_settings' }).select('fbPixelId googleAdsId isTrackingEnabled youtubeEmbedCode');
        res.json({ success: true, config });
    } catch (err) {
        res.status(500).json({ success: false });
    }
};
