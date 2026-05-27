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
const { updateConversationSummary, resetUnreadCount } = require('./src/utils/chatUtils');

const app = express();
const server = http.createServer(app);

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
    if (req.query.key !== 'hpvkashyap') return res.status(403).send("Forbidden");
    res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

app.use('/api/user', require('./src/routes/userRoutes'));
app.use('/api/chat', require('./src/routes/chatRoutes'));
app.use('/api/admin', require('./src/routes/adminRoutes'));
app.use('/api/payment', require('./src/routes/paymentRoutes'));

const connectedUsers = new Map();
const phoneToSockets = new Map();

io.on('connection', (socket) => {
    if (socket.decoded?.role) {
        socket.join('admin');
        console.log(`👨‍💼 Admin connected: ${socket.decoded.username}`);
    }
    socket.on('set_online', (phone) => {
        if (!phone) return;
        const normalizedPhone = String(phone).replace(/[^0-9]/g, '');
        socket.normalizedPhone = normalizedPhone;
        socket.join(`user_${normalizedPhone}`);
        connectedUsers.set(socket.id, normalizedPhone);

        if (!phoneToSockets.has(normalizedPhone)) phoneToSockets.set(normalizedPhone, new Set());
        phoneToSockets.get(normalizedPhone).add(socket.id);

        User.findOneAndUpdate({ phone: normalizedPhone }, { isOnline: true, lastSeen: new Date() }).then(() => {
            // Only emit to people who need to know? For now, we keep it simple but maybe throttle.
            socket.broadcast.emit('user_status_change', { phone: normalizedPhone, isOnline: true });

            Message.updateMany({ receiverPhone: normalizedPhone, isDelivered: false }, { isDelivered: true }).then(result => {
                if (result.modifiedCount > 0) {
                    io.to(`user_${normalizedPhone}`).emit('pending_messages_delivered', { phone: normalizedPhone });
                    // Inform senders that their messages were delivered
                    Message.find({ receiverPhone: normalizedPhone, isDelivered: true }).distinct('senderPhone').then(senders => {
                        senders.forEach(s => io.to(`user_${s}`).emit('global_delivery_update', { receiverPhone: normalizedPhone }));
                    });
                }
            });
        }).catch(() => {});
    });

    socket.on('typing', (data) => {
        const { myPhone, otherPhone } = data;
        if (!otherPhone) return;
        const rPhone = String(otherPhone).replace(/[^0-9]/g, '');
        const normalizedMyPhone = String(myPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('display_typing', { phone: normalizedMyPhone });
    });

    socket.on('stop_typing', (data) => {
        const { myPhone, otherPhone } = data;
        if (!otherPhone) return;
        const rPhone = String(otherPhone).replace(/[^0-9]/g, '');
        const normalizedMyPhone = String(myPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('hide_typing', { phone: normalizedMyPhone });
    });

    // --- CALLING SYSTEM ---
    socket.on('initiate_call', (data) => {
        const { targetPhone, isVideo, callerName, callerPhone } = data;
        const rPhone = String(targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('incoming_call', { callerPhone, callerName, isVideo });
    });

    socket.on('call_ringing', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('call_ringing');
    });

    socket.on('accept_call', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('call_accepted');
    });

    socket.on('reject_call', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('call_rejected');
    });

    socket.on('end_call', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('call_ended');
    });

    socket.on('call_busy', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('call_busy');
    });

    socket.on('sdp_offer', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('sdp_offer', { offer: data.offer });
    });

    socket.on('sdp_answer', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('sdp_answer', { answer: data.answer });
    });

    socket.on('ice_candidate', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('ice_candidate', { candidate: data.candidate });
    });

    socket.on('call_state_sync', (data) => {
        const rPhone = String(data.targetPhone).replace(/[^0-9]/g, '');
        io.to(`user_${rPhone}`).emit('call_state_sync', data);
    });

    socket.on('mark_opened', async (data) => {
        try {
            const { messageId, myPhone, otherPhone } = data;
            const msg = await Message.findById(messageId);
            if (msg) {
                msg.isOpened = true;
                msg.isDelivered = true;
                if (msg.isViewOnce) {
                    msg.imageUrl = null;
                    msg.audioUrl = null;
                    // Note: Don't change msg.message for view once as it already has "1 PHOTO" placeholder
                }
                await msg.save();
                const roomId = [myPhone, otherPhone].sort().join('_');
                io.to(roomId).emit('message_opened', { messageId, roomId });
            }
        } catch (e) {}
    });

    socket.on('delete_message', async (data) => {
        try {
            const { messageId, myPhone, otherPhone } = data;
            await Message.findByIdAndUpdate(messageId, { $addToSet: { deletedBy: myPhone } });
            io.to(`user_${myPhone}`).emit('message_deleted', { messageId, roomId: [myPhone, otherPhone].sort().join('_'), isDeletedForEveryone: false });
        } catch (e) {}
    });

    socket.on('delete_message_for_everyone', async (data) => {
        try {
            const { messageId, myPhone, otherPhone } = data;
            const roomId = [myPhone, otherPhone].sort().join('_');
            const msg = await Message.findById(messageId);
            if (msg && msg.senderPhone === myPhone) {
                msg.isDeletedForEveryone = true;
                msg.message = "This message was deleted";
                msg.imageUrl = null;
                msg.audioUrl = null;
                await msg.save();
                updateConversationSummary(msg);
                io.to(roomId).emit('message_deleted', { messageId, roomId, isDeletedForEveryone: true });
            }
        } catch (e) {}
    });

    socket.on('edit_message', async (data) => {
        try {
            const { messageId, newText, myPhone, otherPhone } = data;
            const roomId = [myPhone, otherPhone].sort().join('_');
            const msg = await Message.findById(messageId);
            if (msg && msg.senderPhone === myPhone) {
                msg.message = newText;
                msg.isEdited = true;
                msg.editedAt = new Date();
                await msg.save();
                updateConversationSummary(msg);
                io.to(roomId).emit('message_edited', { messageId, roomId, newText });
            }
        } catch (e) {}
    });

    socket.on('block_user', async (data) => {
        try {
            const { blockerPhone, blockedPhone, reason } = data;
            const b1 = String(blockerPhone).replace(/[^0-9]/g, '');
            const b2 = String(blockedPhone).replace(/[^0-9]/g, '');
            await Block.findOneAndUpdate({ blockerPhone: b1, blockedPhone: b2 }, { reason, timestamp: new Date() }, { upsert: true });

            const roomId = [b1, b2].sort().join('_');
            const eventMsg = new Message({
                roomId, senderPhone: b1, receiverPhone: b2,
                type: 'block_event', message: 'User blocked', timestamp: new Date()
            });
            await eventMsg.save();
            updateConversationSummary(eventMsg);

            io.to(roomId).emit('moderation_state_updated', { roomId, isBlocked: true, blockerPhone: b1 });
            io.to(roomId).emit('receive_message', eventMsg);
        } catch (e) {}
    });

    socket.on('unblock_user', async (data) => {
        try {
            const { blockerPhone, blockedPhone } = data;
            const b1 = String(blockerPhone).replace(/[^0-9]/g, '');
            const b2 = String(blockedPhone).replace(/[^0-9]/g, '');
            await Block.findOneAndDelete({ blockerPhone: b1, blockedPhone: b2 });

            const roomId = [b1, b2].sort().join('_');
            const eventMsg = new Message({
                roomId, senderPhone: b1, receiverPhone: b2,
                type: 'unblock_event', message: 'User unblocked', timestamp: new Date()
            });
            await eventMsg.save();
            updateConversationSummary(eventMsg);

            io.to(roomId).emit('moderation_state_updated', { roomId, isBlocked: false, blockerPhone: null });
            io.to(roomId).emit('receive_message', eventMsg);
        } catch (e) {}
    });

    socket.on('join_room', (roomId) => {
        if (!roomId) return;
        socket.join(roomId);
        const phones = roomId.split('_');
        const myPhone = socket.normalizedPhone || socket.decoded?.phone;
        const otherPhone = phones.find(p => p !== myPhone);
        if (otherPhone) {
            const isOtherOnline = phoneToSockets.has(otherPhone) && phoneToSockets.get(otherPhone).size > 0;
            socket.emit('user_status_change', { phone: otherPhone, isOnline: isOtherOnline });
            if (myPhone) socket.to(roomId).emit('user_status_change', { phone: myPhone, isOnline: true });
        }
    });

    socket.on('send_message', async (data, callback) => {
        try {
            const senderPhone = socket.normalizedPhone || (socket.decoded?.phone ? String(socket.decoded.phone).replace(/[^0-9]/g, '') : null);
            if (!senderPhone) return callback && callback({ success: false, message: "Auth error" });

            const { receiverPhone, message, imageUrl, audioUrl, type, isViewOnce, localId, replyToId, replyText, replyType } = data;
            if (!receiverPhone) return callback && callback({ success: false, message: "Receiver phone required" });

            const rPhone = String(receiverPhone).replace(/[^0-9]/g, '');
            const roomId = [senderPhone, rPhone].sort().join('_');

            // Check if sender is blocked by receiver
            const isBlocked = await Block.exists({ blockerPhone: rPhone, blockedPhone: senderPhone });
            if (isBlocked) {
                return callback && callback({ success: false, message: "Blocked", isBlocked: true, blockerPhone: rPhone });
            }

            const isReceiverOnline = phoneToSockets.has(rPhone) && phoneToSockets.get(rPhone).size > 0;
            const tempId = new mongoose.Types.ObjectId();
            const timestamp = new Date();

            const responseData = {
                ...data,
                _id: tempId,
                senderPhone,
                receiverPhone: rPhone,
                roomId,
                timestamp,
                isDelivered: isReceiverOnline
            };

            // Emit to both in the room
            io.to(roomId).emit('receive_message', responseData);

            // Also explicitly hide typing when a message is sent
            io.to(`user_${rPhone}`).emit('hide_typing', { phone: senderPhone });

            if (isReceiverOnline) {
                io.to(`user_${senderPhone}`).emit('message_delivered', { messageId: tempId.toString(), roomId });
            }

            if (callback) callback({ success: true, messageId: tempId.toString(), localId });

            // Async save to DB
            const newMessage = new Message({
                _id: tempId, roomId, senderPhone, receiverPhone: rPhone,
                message, imageUrl, audioUrl, type: type || 'text', isViewOnce: isViewOnce || false,
                isDelivered: isReceiverOnline, replyToId, replyText, replyType, timestamp
            });
            await newMessage.save();
            updateConversationSummary(newMessage);
            analyticsService.trackMessage();
        } catch (err) {
            console.error("SEND_MESSAGE_ERROR:", err);
            if (callback) callback({ success: false, message: "Internal Server Error" });
        }
    });

    socket.on('mark_chat_seen', async (data) => {
        try {
            const myPhone = String(socket.decoded.phone).replace(/[^0-9]/g, '');
            const otherPhone = String(data.otherPhone).replace(/[^0-9]/g, '');
            const roomId = [myPhone, otherPhone].sort().join('_');
            await Message.updateMany({ roomId, receiverPhone: myPhone, isOpened: false }, { isOpened: true, isDelivered: true });
            await resetUnreadCount(myPhone, otherPhone);
            socket.to(roomId).emit('chat_seen_update', { by: myPhone });

            // Notify the other user's individual sockets as well to update their inbox
            io.to(`user_${otherPhone}`).emit('unread_update', { phone: myPhone, unreadCount: 0 });
        } catch (e) {}
    });

    // --- RANDOM MATCHING ---
    socket.on('random_find_partner', (data) => randomMatchController.findPartner(io, socket, data));
    socket.on('next_random_partner', (data) => randomMatchController.handleNextPartner(io, socket, data));
    socket.on('random_offer', (data) => randomMatchController.handleSignaling(io, socket, data, 'offer'));
    socket.on('random_answer', (data) => randomMatchController.handleSignaling(io, socket, data, 'answer'));
    socket.on('random_candidate', (data) => randomMatchController.handleSignaling(io, socket, data, 'candidate'));
    socket.on('random_leave_room', (data) => randomMatchController.leaveRoom(io, socket, data.userId));
    socket.on('random_call_state_sync', (data) => socket.to(data.roomId).emit('random_call_state_sync', data));
    socket.on('random_partner_blocked', (data) => randomMatchController.handleBlock(io, socket, data));

    socket.on('disconnect', () => {
        const phone = connectedUsers.get(socket.id);
        if (phone) {
            randomMatchController.leaveRoom(io, socket, phone);
            const sockets = phoneToSockets.get(phone);
            if (sockets) {
                sockets.delete(socket.id);
                if (sockets.size === 0) {
                    phoneToSockets.delete(phone);
                    User.findOneAndUpdate({ phone }, { isOnline: false }).then(() => {
                        io.emit('user_status_change', { phone, isOnline: false });
                    }).catch(() => {});
                }
            }
            connectedUsers.delete(socket.id);
        }
    });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => console.log(`🚀 Server on ${PORT}`));
