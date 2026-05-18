const Policy = require('../models/Policy');

exports.getPolicies = async (req, res) => {
    try {
        const policies = await Policy.find();
        res.json({ success: true, policies });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

exports.updatePolicy = async (req, res) => {
    try {
        const { type, url } = req.body;
        await Policy.findOneAndUpdate(
            { type },
            { url, updatedAt: new Date() },
            { upsert: true, new: true }
        );
        res.json({ success: true, message: "Policy updated successfully" });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

// For Flutter App to get a specific policy URL
exports.getPolicyByType = async (req, res) => {
    try {
        const policy = await Policy.findOne({ type: req.params.type });
        if (policy) res.json({ success: true, url: policy.url });
        else res.json({ success: false, message: "Policy not found" });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};
