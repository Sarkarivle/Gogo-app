const ContactMessage = require('../models/ContactMessage');
const User = require('../models/User');

// For App: Submit Contact Form
exports.submitMessage = async (req, res) => {
    try {
        const { phone, category, message, subject, name, email } = req.body;

        // Fetch User context if available
        let userContext = {};
        if (phone) {
            const user = await User.findOne({ phone });
            if (user) {
                userContext = {
                    userId: user._id,
                    premiumStatus: user.isPremium || false,
                    deviceInfo: req.headers['user-agent'] || 'Unknown',
                    signupDate: user.createdAt,
                    reportCount: 0, // Should be fetched from Report model
                    activityScore: user.activityScore || 0
                };
            }
        }

        const newMessage = new ContactMessage({
            name, phone, email, subject, message, category,
            userPhone: phone,
            userContext
        });

        await newMessage.save();

        // Emit Realtime Event to Admin Panel
        const io = req.app.get('socketio');
        if (io) {
            io.emit('new_support_ticket', newMessage);
            // Critical alert for admins
            if (newMessage.priority === 'Critical') {
                io.emit('admin_critical_alert', {
                    type: 'SUPPORT_CRITICAL',
                    title: 'CRITICAL SUPPORT TICKET',
                    message: `Category: ${newMessage.category} - ${newMessage.name}`,
                    ticketId: newMessage._id
                });
            }
        }

        res.json({ success: true, message: "Ticket created successfully.", ticketId: newMessage._id });
    } catch (error) {
        console.error("Submit Support Message Error:", error);
        res.status(500).json({ success: false });
    }
};

// For Admin: Get all messages (with filters and pagination)
exports.getMessages = async (req, res) => {
    try {
        const { status, category, priority, assignedTo, page = 1, limit = 50 } = req.query;
        let query = {};
        if (status) query.status = status;
        if (category) query.category = category;
        if (priority) query.priority = priority;
        if (assignedTo) query.assignedTo = assignedTo;

        const skip = (parseInt(page) - 1) * parseInt(limit);
        const messages = await ContactMessage.find(query)
            .sort({ priority: -1, createdAt: -1 }) // Priority first
            .skip(skip)
            .limit(parseInt(limit));

        const total = await ContactMessage.countDocuments(query);

        res.json({
            success: true,
            messages,
            pagination: {
                total,
                page: parseInt(page),
                limit: parseInt(limit),
                pages: Math.ceil(total / limit)
            }
        });
    } catch (error) {
        res.status(500).json({ success: false, messages: [] });
    }
};

// For Admin: Update Ticket (Status, Reply, Priority, Category)
exports.updateMessageStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const updateData = req.body; // adminReply, status, priority, category

        const ticket = await ContactMessage.findById(id);
        if (!ticket) return res.status(404).json({ success: false, message: "Ticket not found" });

        // track first response time
        if (!ticket.responseStartAt && (updateData.adminReply || updateData.status !== 'Pending')) {
            ticket.responseStartAt = new Date();
            ticket.responseTimeMs = ticket.responseStartAt - ticket.createdAt;
        }

        // handle resolution
        if (updateData.status === 'Resolved' || updateData.status === 'Closed') {
            ticket.resolvedAt = new Date();
            ticket.resolutionTimeMs = ticket.resolvedAt - ticket.createdAt;
            // ticket.resolvedBy = req.admin._id; // If auth is available
        }

        Object.assign(ticket, updateData);
        await ticket.save();

        // Emit update
        const io = req.app.get('socketio');
        if (io) io.emit('support_ticket_updated', ticket);

        res.json({ success: true, ticket });
    } catch (error) {
        res.status(500).json({ success: false });
    }
};

// For Admin: Assign Ticket
exports.assignTicket = async (req, res) => {
    try {
        const { id } = req.params;
        const { adminId, adminName, assignedBy, assignedByName } = req.body;

        const ticket = await ContactMessage.findByIdAndUpdate(id, {
            assignedTo: adminId,
            assignedToName: adminName,
            assignedBy: assignedBy,
            assignedAt: new Date(),
            status: 'In Review'
        }, { new: true });

        const io = req.app.get('socketio');
        if (io) io.emit('support_ticket_updated', ticket);

        res.json({ success: true, ticket });
    } catch (e) { res.status(500).json({ success: false }); }
};

// For Admin: Add Internal Note
exports.addInternalNote = async (req, res) => {
    try {
        const { id } = req.params;
        const { note, adminName, adminId } = req.body;

        const ticket = await ContactMessage.findById(id);
        ticket.internalNotes.push({ note, adminName, adminId });
        await ticket.save();

        const io = req.app.get('socketio');
        if (io) io.emit('support_ticket_updated', ticket);

        res.json({ success: true, ticket });
    } catch (e) { res.status(500).json({ success: false }); }
};

// Get Ticket Detail
exports.getTicketDetail = async (req, res) => {
    try {
        const ticket = await ContactMessage.findById(req.params.id);
        res.json({ success: true, ticket });
    } catch (e) { res.status(500).json({ success: false }); }
};
