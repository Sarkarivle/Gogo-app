require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const http = require('http');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const connectDB = require('./src/config/db');

// Models
const User = require('./src/models/User');
const Message = require('./src/models/Message');
const Block = require('./src/models/Block');

// Services
const analyticsService = require('./src/services/analyticsService');
const revenueService = require('./src/services/revenueService');
const notificationService = require('./src/services/notificationService');
const randomMatchController = require('./src/controllers/RandomMatchController');
const { normalize, phoneQuery } = require('./src/utils/phoneUtils');
const { updateConversationSummary, resetUnreadCount } = require('./src/utils/chatUtils');

const app = express();
const server = http.createServer(app);

// --- STARTUP CHECKS ---
if (!process.env.JWT_SECRET) {
    console.warn("⚠️ WARNING: JWT_SECRET is not set in .env. Using default (INSECURE)");
}
if (!process.env.ADMIN_PANEL_KEY) {
    console.warn("⚠️ WARNING: ADMIN_PANEL_KEY is not set. Admin panel path is vulnerable.");
}

// --- HELPERS ---
const normalizePhone = normalize;

const getRoomId = (p1, p2) => [normalize(p1), normalize(p2)].sort().join('_');

// --- SECURITY MIDDLEWARES ---
const helmet = require('helmet');
const mongoSanitize = require('express-mongo-sanitize');
const rateLimit = require('express-rate-limit');

app.use(helmet({ contentSecurityPolicy: false, crossOriginEmbedderPolicy: false }));
app.use(mongoSanitize());
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 2000, message: { success: false, message: "Too many requests" } });
app.use('/api/', limiter);

const io = new Server(server, { cors: { origin: "*" }, pingTimeout: 20000, pingInterval: 5000, transports: ['websocket'] });

const jwt = require('jsonwebtoken');
// IMPORTANT: In production, always set JWT_SECRET in .env
const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

if (process.env.NODE_ENV === 'production' && !process.env.JWT_SECRET) {
    console.error("❌ CRITICAL: JWT_SECRET is missing in production environment!");
    process.exit(1);
}

io.use((socket, next) => {
    const token = socket.handshake.auth?.token || socket.handshake.query?.token;
    if (!token) return next(new Error("Auth error"));
    try {
        const decoded = jwt.verify(token, JWT_SECRET);
        socket.decoded = decoded;
        socket.userPhone = normalizePhone(decoded.phone);
        next();
    } catch (err) { return next(new Error("Auth error")); }
});

connectDB();
analyticsService.init(io);
revenueService.init(io);

setInterval(() => { randomMatchController.performGlobalCleanup(); }, 120000);

app.set('socketio', io);
app.use(cors());
app.use(express.json());

// Global Request Logger for Debugging
app.use((req, res, next) => {
    if (!req.url.includes('/media/')) {
        console.log(`🌐 [${new Date().toISOString()}] ${req.method} ${req.url}`);
    }
    next();
});

app.get('/api/media/:filename', require('./src/controllers/ChatController').serveSecureMedia);
app.use(express.static(path.join(__dirname, 'public')));
app.get('/', (req, res) => res.send('🚀 GoGo Backend Running!'));

app.get('/admin', (req, res) => {
    const ADMIN_KEY = process.env.ADMIN_PANEL_KEY;
    if (!ADMIN_KEY) return res.status(500).send("Server Configuration Error: Admin Key missing");

    // Allow both ?key=secret and just ?secret for convenience
    const isAuthorized = req.query.key === ADMIN_KEY || req.query[ADMIN_KEY] !== undefined;

    if (!isAuthorized) return res.status(403).send("Forbidden");
    res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

const { isUser, isAdmin } = require('./src/middleware/auth');

app.use('/api/user', require('./src/routes/userRoutes'));
app.use('/api/chat', require('./src/routes/chatRoutes'));
app.use('/api/admin', require('./src/routes/adminRoutes'));
app.use('/api/payment', require('./src/routes/paymentRoutes'));
app.use('/api/review', require('./src/routes/reviewRoutes'));

// --- GLOBAL ERROR HANDLING (PREVENTS CRASHES) ---
process.on('uncaughtException', (err) => {
    console.error('❌ FATAL: Uncaught Exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('❌ FATAL: Unhandled Rejection at:', promise, 'reason:', reason);
});

const phoneToSockets = new Map();

io.on('connection', (socket) => {
    const myPhone = socket.userPhone;

    if (socket.decoded?.role) {
        socket.join('admin');
        console.log(`👨‍💼 Admin connected: ${socket.decoded.username}`);
    }

    if (myPhone) {
        socket.join(`user_${myPhone}`);
        if (!phoneToSockets.has(myPhone)) phoneToSockets.set(myPhone, new Set());
        phoneToSockets.get(myPhone).add(socket.id);
    }

    socket.on('set_online', async (phone) => {
        // Security: Use myPhone from socket to prevent spoofing other users
        const normalized = myPhone;
        if (!normalized) return;

        try {
            await User.findOneAndUpdate({ phone: normalized }, { isOnline: true, lastSeen: new Date() });
            socket.broadcast.emit('user_status_change', { phone: normalized, isOnline: true });

            const result = await Message.updateMany({ receiverPhone: normalized, isDelivered: false }, { isDelivered: true });
            if (result.modifiedCount > 0) {
                io.to(`user_${normalized}`).emit('pending_messages_delivered', { phone: normalized });
                const senders = await Message.find({ receiverPhone: normalized, isDelivered: true }).distinct('senderPhone');
                senders.forEach(s => io.to(`user_${normalize(s)}`).emit('global_delivery_update', { receiverPhone: normalized }));
            }
        } catch (e) {
            console.error("set_online error:", e);
        }
    });

    socket.on('typing', (data) => {
        const other = normalizePhone(data.otherPhone);
        if (other) io.to(`user_${other}`).emit('display_typing', { phone: myPhone });
    });

    socket.on('stop_typing', (data) => {
        const other = normalizePhone(data.otherPhone);
        if (other) io.to(`user_${other}`).emit('hide_typing', { phone: myPhone });
    });

    // --- CALLING SYSTEM ---
    socket.on('initiate_call', (data) => {
        const other = normalizePhone(data.targetPhone || data.receiverPhone);
        if (other) io.to(`user_${other}`).emit('incoming_call', { callerPhone: myPhone, callerName: data.callerName, isVideo: data.isVideo });
    });

    socket.on('call_ringing', (data) => {
        const other = normalizePhone(data.targetPhone || data.callerPhone);
        if (other) io.to(`user_${other}`).emit('call_ringing', { receiverPhone: myPhone });
    });

    socket.on('accept_call', (data) => {
        const other = normalizePhone(data.targetPhone || data.callerPhone);
        if (other) io.to(`user_${other}`).emit('call_accepted', { receiverPhone: myPhone });
    });

    socket.on('reject_call', (data) => {
        const other = normalizePhone(data.targetPhone || data.callerPhone);
        if (other) io.to(`user_${other}`).emit('call_rejected', { receiverPhone: myPhone, reason: data.reason });
    });

    socket.on('end_call', (data) => {
        const other = normalizePhone(data.targetPhone || data.otherPhone);
        if (other) io.to(`user_${other}`).emit('call_ended', { by: myPhone });
    });

    socket.on('sdp_offer', (data) => {
        const other = normalizePhone(data.targetPhone || data.otherPhone);
        if (other) io.to(`user_${other}`).emit('sdp_offer', { offer: data.offer, sdp: data.sdp, from: myPhone });
    });

    socket.on('sdp_answer', (data) => {
        const other = normalizePhone(data.targetPhone || data.otherPhone);
        if (other) io.to(`user_${other}`).emit('sdp_answer', { answer: data.answer, sdp: data.sdp, from: myPhone });
    });

    socket.on('ice_candidate', (data) => {
        const other = normalizePhone(data.targetPhone || data.otherPhone);
        if (other) io.to(`user_${other}`).emit('ice_candidate', { candidate: data.candidate, from: myPhone });
    });

    socket.on('mark_opened', async (data) => {
        try {
            const { messageId, otherPhone } = data;
            const msg = await Message.findById(messageId);
            // Security: Ensure only the receiver can mark a message as opened
            if (msg && normalizePhone(msg.receiverPhone) === myPhone) {
                msg.isOpened = true;
                msg.isDelivered = true;
                if (msg.isViewOnce) {
                    msg.imageUrl = null;
                    msg.audioUrl = null;
                }
                await msg.save();
                const roomId = getRoomId(myPhone, otherPhone);
                io.to(roomId).emit('message_opened', { messageId, roomId });
            }
        } catch (e) {
            console.error("mark_opened error:", e);
        }
    });

    socket.on('delete_message', async (data) => {
        try {
            const { messageId, otherPhone } = data;
            const msg = await Message.findById(messageId);
            // Security: Ensure the user is part of the conversation before deleting
            if (msg && (normalizePhone(msg.senderPhone) === myPhone || normalizePhone(msg.receiverPhone) === myPhone)) {
                await Message.findByIdAndUpdate(messageId, { $addToSet: { deletedBy: myPhone } });
                io.to(`user_${myPhone}`).emit('message_deleted', { messageId, roomId: getRoomId(myPhone, otherPhone), isDeletedForEveryone: false });
            }
        } catch (e) {
            console.error("delete_message error:", e);
        }
    });

    socket.on('delete_message_for_everyone', async (data) => {
        try {
            const { messageId, otherPhone } = data;
            const roomId = getRoomId(myPhone, otherPhone);
            const msg = await Message.findById(messageId);
            if (msg && normalizePhone(msg.senderPhone) === myPhone) {
                msg.isDeletedForEveryone = true;
                msg.message = "This message was deleted";
                msg.imageUrl = null;
                msg.audioUrl = null;
                await msg.save();
                updateConversationSummary(msg);
                io.to(roomId).emit('message_deleted', { messageId, roomId, isDeletedForEveryone: true });
            }
        } catch (e) {
            console.error("delete_message_for_everyone error:", e);
        }
    });

    socket.on('edit_message', async (data) => {
        try {
            const { messageId, newText, otherPhone } = data;
            const roomId = getRoomId(myPhone, otherPhone);
            const msg = await Message.findById(messageId);
            if (msg && normalizePhone(msg.senderPhone) === myPhone) {
                msg.message = newText;
                msg.isEdited = true;
                msg.editedAt = new Date();
                await msg.save();
                updateConversationSummary(msg);
                io.to(roomId).emit('message_edited', { messageId, roomId, newText });
            }
        } catch (e) {
            console.error("edit_message error:", e);
        }
    });

    socket.on('block_user', async (data) => {
        try {
            const b1 = myPhone;
            const b2 = normalizePhone(data.blockedPhone);
            await Block.findOneAndUpdate({ blockerPhone: b1, blockedPhone: b2 }, { reason: data.reason, timestamp: new Date() }, { upsert: true });

            const roomId = getRoomId(b1, b2);
            const eventMsg = new Message({
                roomId, senderPhone: b1, receiverPhone: b2,
                type: 'block_event', message: 'User blocked', timestamp: new Date()
            });
            await eventMsg.save();
            updateConversationSummary(eventMsg);

            io.to(roomId).emit('moderation_state_updated', { roomId, isBlocked: true, blockerPhone: b1 });
            io.to(roomId).emit('receive_message', eventMsg);
        } catch (e) {
            console.error("block_user error:", e);
        }
    });

    socket.on('unblock_user', async (data) => {
        try {
            const b1 = myPhone;
            const b2 = normalizePhone(data.blockedPhone);
            await Block.findOneAndDelete({ blockerPhone: b1, blockedPhone: b2 });

            const roomId = getRoomId(b1, b2);
            const eventMsg = new Message({
                roomId, senderPhone: b1, receiverPhone: b2,
                type: 'unblock_event', message: 'User unblocked', timestamp: new Date()
            });
            await eventMsg.save();
            updateConversationSummary(eventMsg);

            io.to(roomId).emit('moderation_state_updated', { roomId, isBlocked: false, blockerPhone: null });
            io.to(roomId).emit('receive_message', eventMsg);
        } catch (e) {
            console.error("unblock_user error:", e);
        }
    });

    socket.on('send_message', async (data, callback) => {
        try {
            if (!myPhone) return callback && callback({ success: false, message: "Auth error" });
            const receiver = normalizePhone(data.receiverPhone);
            if (!receiver) return callback && callback({ success: false, message: "Receiver required" });

            const roomId = getRoomId(myPhone, receiver);
            const isReceiverOnline = phoneToSockets.has(receiver) && phoneToSockets.get(receiver).size > 0;

            const tempId = new mongoose.Types.ObjectId();
            const timestamp = new Date();

            const responseData = { ...data, _id: tempId, senderPhone: myPhone, receiverPhone: receiver, roomId, timestamp, isDelivered: isReceiverOnline };

            io.to(roomId).emit('receive_message', responseData);
            io.to(`user_${receiver}`).emit('hide_typing', { phone: myPhone });

            if (isReceiverOnline) io.to(`user_${myPhone}`).emit('message_delivered', { messageId: tempId.toString(), roomId });
            if (callback) callback({ success: true, messageId: tempId.toString(), localId: data.localId });

            const newMessage = new Message({
                _id: tempId, roomId, senderPhone: myPhone, receiverPhone: receiver,
                localId: data.localId, // Save client's local ID
                message: data.message, imageUrl: data.imageUrl, audioUrl: data.audioUrl,
                type: data.type || 'text', isViewOnce: data.isViewOnce || false,
                isDelivered: isReceiverOnline, replyToId: data.replyToId, replyText: data.replyText, replyType: data.replyType, timestamp
            });
            await newMessage.save();
            updateConversationSummary(newMessage);

            // --- SEND PUSH NOTIFICATION ---
            try {
                const receiverUser = await User.findOne({ phone: receiver }, 'fcmToken');
                if (receiverUser?.fcmToken) {
                    const senderUser = await User.findOne({ phone: myPhone }, 'name position');
                    const senderName = senderUser?.name || "Someone";

                    let body = data.message;
                    if (data.type === 'image') body = "📷 Sent an image";
                    else if (data.type === 'audio') body = "🎵 Sent a voice message";
                    else if (data.type === 'video') body = "🎥 Sent a video";

                    const result = await notificationService.sendPushNotification(
                        receiverUser.fcmToken,
                        senderName,
                        body,
                        {
                            type: 'chat',
                            senderPhone: myPhone,
                            senderName: senderName,
                            senderPosition: senderUser?.position || "Member",
                            roomId: roomId,
                            messageId: tempId.toString()
                        }
                    );

                    // If token is invalid, clear it from DB to stop future failed attempts
                    if (result && result.isInvalidToken) {
                        console.log(`🧹 Cleaning up invalid FCM token for user: ${receiver}`);
                        await User.updateOne({ phone: receiver }, { $unset: { fcmToken: 1 } });
                    }
                }
            } catch (notifyErr) {
                console.error("FCM Send Error in server.js:", notifyErr.message);
            }
        } catch (err) {
            console.error("SEND_MESSAGE_ERROR:", err);
            if (callback) callback({ success: false });
        }
    });

    socket.on('mark_chat_seen', async (data) => {
        try {
            const other = normalize(data.otherPhone);
            const roomId = getRoomId(myPhone, other);

            // SECURITY FIX: Only mark normal messages as 'Opened' (Seen).
            // 'View Once' messages MUST NOT be marked as opened automatically; they only open on tap.
            await Message.updateMany(
                { roomId, receiverPhone: myPhone, isOpened: false, isViewOnce: false },
                { isOpened: true, isDelivered: true }
            );

            // For View Once, just ensure they are marked as Delivered (two ticks) but NOT opened.
            await Message.updateMany(
                { roomId, receiverPhone: myPhone, isDelivered: false, isViewOnce: true },
                { isDelivered: true }
            );

            await resetUnreadCount(myPhone, other);
            socket.to(roomId).emit('chat_seen_update', { by: myPhone });
            io.to(`user_${other}`).emit('unread_update', { phone: myPhone, unreadCount: 0 });
        } catch (e) {
            console.error("mark_chat_seen error:", e);
        }
    });

    socket.on('join_room', (roomId) => {
        if (!roomId) return;
        const parts = roomId.split('_').map(p => normalizePhone(p));

        // Security: Only allow joining rooms that the user is actually a part of
        if (!parts.includes(myPhone)) {
            console.warn(`Unauthorized room join attempt by ${myPhone} to ${roomId}`);
            return;
        }

        const cleanRoomId = parts.sort().join('_');
        socket.join(cleanRoomId);

        const other = parts.find(p => p !== myPhone);
        if (other) {
            const isOnline = phoneToSockets.has(other) && phoneToSockets.get(other).size > 0;
            socket.emit('user_status_change', { phone: other, isOnline });
        }
    });

    // --- RANDOM MATCHING SYSTEM ---
    socket.on('find_partner', (data) => randomMatchController.findPartner(io, socket, data));
    socket.on('leave_random_room', () => randomMatchController.leaveRoom(io, socket));
    socket.on('next_partner', (data) => randomMatchController.handleNextPartner(io, socket, data));
    socket.on('random_offer', (data) => randomMatchController.handleSignaling(io, socket, data, 'offer'));
    socket.on('random_answer', (data) => randomMatchController.handleSignaling(io, socket, data, 'answer'));
    socket.on('random_candidate', (data) => randomMatchController.handleSignaling(io, socket, data, 'candidate'));
    socket.on('random_block', (data) => randomMatchController.handleBlock(io, socket, data));

    socket.on('disconnect', () => {
        if (myPhone) {
            const sockets = phoneToSockets.get(myPhone);
            if (sockets) {
                sockets.delete(socket.id);
                if (sockets.size === 0) {
                    phoneToSockets.delete(myPhone);
                    User.findOneAndUpdate({ phone: myPhone }, { isOnline: false }).then(() => {
                        io.emit('user_status_change', { phone: myPhone, isOnline: false });
                    }).catch(e => console.error("Disconnect status update error:", e));
                }
            }
        }
    });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => console.log(`🚀 Server on ${PORT}`));
