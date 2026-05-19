const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const http = require('http');
const { Server } = require('socket.io');
const connectDB = require('./src/config/db');

// Models
const User = require('./src/models/User');
const Message = require('./src/models/Message');
const Block = require('./src/models/Block');

// Controllers
const UserController = require('./src/controllers/UserController');
const ChatController = require('./src/controllers/ChatController');

// Services
const notificationService = require('./src/services/notificationService');

// Routes
const userRoutes = require('./src/routes/userRoutes');
const chatRoutes = require('./src/routes/chatRoutes');
const adminRoutes = require('./src/routes/adminRoutes');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: "*" },
    pingTimeout: 60000,
});

connectDB();

app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use(express.static(path.join(__dirname, 'public')));

// --- CORE APIs ---
app.post('/api/login', UserController.login);
app.post('/api/register', UserController.register);
app.get('/api/inbox/:phone', ChatController.getInbox);
app.post('/api/messages/mark-seen', ChatController.markSeen);

// --- MODULAR APIs ---
app.use('/api/user', userRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/admin', adminRoutes);

// Admin Route
app.get('/admin', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

app.get('/', (req, res) => res.json({ status: "Active", version: "2.0.0" }));

const connectedUsers = new Map(); // socket.id -> phone
const phoneToSockets = new Map(); // phone -> Set of socket.ids

io.on('connection', (socket) => {
    console.log(`Socket Connected: ${socket.id}`);

    socket.on('set_online', async (phone) => {
        if (!phone) return;

        connectedUsers.set(socket.id, phone);
        if (!phoneToSockets.has(phone)) {
            phoneToSockets.set(phone, new Set());
        }
        phoneToSockets.get(phone).add(socket.id);

        // Mark online in DB and notify others
        const user = await User.findOne({ phone });
        if (user && !user.isOnline) {
            await User.findOneAndUpdate({ phone }, { isOnline: true, lastSeen: new Date() });
            io.emit('user_status_change', { phone, isOnline: true });
        }

        // Deliver pending messages
        try {
            const undelivered = await Message.find({ receiverPhone: phone, isDelivered: false });
            for (let msg of undelivered) {
                msg.isDelivered = true;
                await msg.save();
                const senderRoom = [msg.senderPhone, msg.receiverPhone].sort().join('_');
                io.to(senderRoom).emit('message_delivered', { messageId: msg._id });
            }
        } catch (err) {
            console.log("Error delivering pending messages:", err);
        }
    });

    socket.on('join_room', async (roomId) => {
        socket.join(roomId);
        const phones = roomId.split('_');
        const myPhone = connectedUsers.get(socket.id);
        const otherPhone = phones.find(p => p !== myPhone);

        if (otherPhone) {
            const isOtherOnline = phoneToSockets.has(otherPhone) && phoneToSockets.get(otherPhone).size > 0;
            socket.emit('user_status_change', { phone: otherPhone, isOnline: isOtherOnline });
        }
    });

    socket.on('typing', (data) => {
        const roomId = [data.myPhone, data.otherPhone].sort().join('_');
        socket.to(roomId).emit('display_typing', { phone: data.myPhone });

        const otherSockets = phoneToSockets.get(data.otherPhone);
        if (otherSockets) {
            otherSockets.forEach(sId => io.to(sId).emit('display_typing', { phone: data.myPhone }));
        }
    });

    socket.on('stop_typing', (data) => {
        const roomId = [data.myPhone, data.otherPhone].sort().join('_');
        socket.to(roomId).emit('hide_typing', { phone: data.myPhone });

        const otherSockets = phoneToSockets.get(data.otherPhone);
        if (otherSockets) {
            otherSockets.forEach(sId => io.to(sId).emit('hide_typing', { phone: data.myPhone }));
        }
    });

    socket.on('notify_block', (data) => {
        const roomId = [data.blockerPhone, data.blockedPhone].sort().join('_');
        io.to(roomId).emit('receive_message', {
            _id: 'system_' + Date.now(),
            senderPhone: data.blockerPhone,
            receiverPhone: data.blockedPhone,
            message: 'You blocked this user',
            type: 'block_event',
            timestamp: new Date()
        });
        io.to(roomId).emit('chat_status_update', { status: 'blocked', by: data.blockerPhone });
    });

    socket.on('notify_unblock', (data) => {
        const roomId = [data.blockerPhone, data.blockedPhone].sort().join('_');
        io.to(roomId).emit('receive_message', {
            _id: 'system_' + Date.now(),
            senderPhone: data.blockerPhone,
            receiverPhone: data.blockedPhone,
            message: 'Unblocked',
            type: 'unblock_event',
            timestamp: new Date()
        });
        io.to(roomId).emit('chat_status_update', { status: 'active' });
    });

    socket.on('send_message', async (data) => {
        try {
            const sender = await User.findOne({ phone: data.senderPhone }, 'accountStatus');
            if (sender && (sender.accountStatus === 'Deactivated' || sender.accountStatus === 'Suspended')) {
                return socket.emit('error_message', { message: "account deactivate" });
            }

            const isBlocked = await Block.findOne({
                $or: [
                    { blockerPhone: data.senderPhone, blockedPhone: data.receiverPhone },
                    { blockerPhone: data.receiverPhone, blockedPhone: data.senderPhone }
                ]
            });

            if (isBlocked) return socket.emit('error_message', { message: "User blocked" });

            const users = [data.senderPhone, data.receiverPhone].sort();
            const roomId = users.join('_');

            const isReceiverOnline = phoneToSockets.has(data.receiverPhone);

            const newMessage = new Message({
                roomId,
                senderPhone: data.senderPhone,
                receiverPhone: data.receiverPhone,
                message: data.message,
                imageUrl: data.imageUrl,
                audioUrl: data.audioUrl,
                type: data.type || (data.audioUrl ? 'audio' : (data.imageUrl ? 'image' : 'text')),
                isViewOnce: data.isViewOnce || false,
                isDelivered: isReceiverOnline
            });
            const savedMsg = await newMessage.save();
            data._id = savedMsg._id;
            data.type = savedMsg.type;
            data.timestamp = savedMsg.timestamp;
            data.isViewOnce = savedMsg.isViewOnce;
            data.isDelivered = savedMsg.isDelivered;

            io.to(roomId).emit('receive_message', data);

            // Notification
            const receiverUser = await User.findOne({ phone: data.receiverPhone }, 'fcmToken name');
            const senderUser = await User.findOne({ phone: data.senderPhone }, 'name position');
            if (receiverUser && receiverUser.fcmToken) {
                const notifTitle = senderUser ? senderUser.name : "New Message";
                const notifBody = data.type === 'audio' ? "🎵 Voice Message" : (data.imageUrl ? "📷 Photo" : data.message);
                notificationService.sendPushNotification(receiverUser.fcmToken, notifTitle, notifBody, {
                    senderPhone: String(data.senderPhone),
                    senderName: String(senderUser ? senderUser.name : "User"),
                    senderPosition: String(senderUser ? senderUser.position : "Member")
                });
            }
        } catch (e) { console.log("Socket Error:", e); }
    });

    socket.on('mark_opened', async (data) => {
        try {
            await Message.findByIdAndUpdate(data.messageId, { isOpened: true, isDelivered: true });
            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            io.to(roomId).emit('message_opened', { messageId: data.messageId });
        } catch (e) {}
    });

    socket.on('mark_chat_seen', async (data) => {
        try {
            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            await Message.updateMany(
                { roomId, receiverPhone: data.myPhone, isOpened: false },
                { isOpened: true, isDelivered: true }
            );
            socket.to(roomId).emit('chat_seen_update', { by: data.myPhone });
        } catch (e) {
            console.log("Error marking chat seen:", e);
        }
    });

    socket.on('disconnect', async () => {
        const phone = connectedUsers.get(socket.id);
        if (phone) {
            const sockets = phoneToSockets.get(phone);
            if (sockets) {
                sockets.delete(socket.id);
                if (sockets.size === 0) {
                    phoneToSockets.delete(phone);
                    await User.findOneAndUpdate({ phone }, { isOnline: false, lastSeen: new Date() });
                    io.emit('user_status_change', { phone, isOnline: false });
                }
            }
            connectedUsers.delete(socket.id);
        }
        console.log(`Socket Disconnected: ${socket.id}`);
    });

    socket.on('delete_message', async (data) => {
        try {
            await Message.findByIdAndDelete(data.messageId);
            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            io.to(roomId).emit('message_deleted', { messageId: data.messageId });
        } catch (e) {}
    });

    socket.on('edit_message', async (data) => {
        try {
            await Message.findByIdAndUpdate(data.messageId, { message: data.newText });
            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            io.to(roomId).emit('message_edited', { messageId: data.messageId, newText: data.newText });
        } catch (e) {}
    });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server is LIVE on port ${PORT}`);
});
