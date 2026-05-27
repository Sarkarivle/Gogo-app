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
const randomMatchController = require('./src/controllers/RandomMatchController');
const { normalize, phoneQuery } = require('./src/utils/phoneUtils');
const { updateConversationSummary, resetUnreadCount } = require('./src/utils/chatUtils');

const app = express();
const server = http.createServer(app);

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
const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

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

app.get('/api/media/:filename', require('./src/controllers/ChatController').serveSecureMedia);
app.use(express.static(path.join(__dirname, 'public')));
app.get('/', (req, res) => res.send('🚀 GoGo Backend Running!'));

app.get('/admin', (req, res) => {
    const ADMIN_KEY = process.env.ADMIN_PANEL_KEY || 'hpvkashyap';
    if (req.query.key !== ADMIN_KEY) return res.status(403).send("Forbidden");
    res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

app.use('/api/user', require('./src/routes/userRoutes'));
app.use('/api/chat', require('./src/routes/chatRoutes'));
app.use('/api/admin', require('./src/routes/adminRoutes'));
app.use('/api/payment', require('./src/routes/paymentRoutes'));

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

    socket.on('set_online', (phone) => {
        // Security: Use myPhone from socket to prevent spoofing other users
        const normalized = myPhone;
        if (!normalized) return;

        User.findOneAndUpdate({ phone: normalized }, { isOnline: true, lastSeen: new Date() }).then(() => {
            socket.broadcast.emit('user_status_change', { phone: normalized, isOnline: true });

            Message.updateMany({ receiverPhone: normalized, isDelivered: false }, { isDelivered: true }).then(result => {
                if (result.modifiedCount > 0) {
                    io.to(`user_${normalized}`).emit('pending_messages_delivered', { phone: normalized });
                    Message.find({ receiverPhone: normalized, isDelivered: true }).distinct('senderPhone').then(senders => {
                        senders.forEach(s => io.to(`user_${normalize(s)}`).emit('global_delivery_update', { receiverPhone: normalized }));
                    });
                }
            }).catch(e => console.error("set_online updateMany error:", e));
        }).catch(e => console.error("set_online findOneAndUpdate error:", e));
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
                message: data.message, imageUrl: data.imageUrl, audioUrl: data.audioUrl,
                type: data.type || 'text', isViewOnce: data.isViewOnce || false,
                isDelivered: isReceiverOnline, replyToId: data.replyToId, replyText: data.replyText, replyType: data.replyType, timestamp
            });
            await newMessage.save();
            updateConversationSummary(newMessage);
        } catch (err) {
            console.error("SEND_MESSAGE_ERROR:", err);
            if (callback) callback({ success: false });
        }
    });

    socket.on('mark_chat_seen', async (data) => {
        try {
            const other = normalize(data.otherPhone);
            const roomId = getRoomId(myPhone, other);
            await Message.updateMany({ roomId, receiverPhone: myPhone, isOpened: false }, { isOpened: true, isDelivered: true });
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
