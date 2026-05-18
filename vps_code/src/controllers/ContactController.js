const ContactMessage = require('../models/ContactMessage');

// For App: Submit Contact Form
exports.submitMessage = async (req, res) => {
    try {
        const newMessage = new ContactMessage(req.body);
        await newMessage.save();
        res.json({ success: true, message: "Your message has been sent. We will contact you soon." });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

// For Admin: Get all messages
exports.getMessages = async (req, res) => {
    try {
        const { status } = req.query;
        let query = {};
        if (status) query.status = status;
        const messages = await ContactMessage.find(query).sort({ createdAt: -1 });
        res.json(messages);
    } catch (error) {
        res.status(500).json([]);
    }
};

// For Admin: Reply and Resolve
exports.updateMessageStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { adminReply, status } = req.body;
        await ContactMessage.findByIdAndUpdate(id, { adminReply, status });
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};
