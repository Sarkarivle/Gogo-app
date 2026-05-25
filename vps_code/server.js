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
const notificationService = require('./src/services/notificationService');
const analyticsService = require('./src/services/analyticsService');
const revenueService = require('./src/services/revenueService');
const randomMatchController = require('./src/controllers/RandomMatchController');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: "*" },
    pingTimeout: 20000,
    pingInterval: 5000,
    transports: ['websocket']
});

connectDB();
analyticsService.init(io);
revenueService.init(io);

// Global Stale Queue Cleanup (Every 2 minutes)
setInterval(() => {
    randomMatchController.performGlobalCleanup();
}, 120000);

app.set('socketio', io); // Set socket.io instance to app for global access

app.use(cors());
app.use(express.json());

// --- DEEP PRODUCTION LOGGER ---
app.use((req, res, next) => {
    const start = Date.now();
    const requestId = Math.random().toString(36).substring(7);
    console.log(`[${new Date().toISOString()}] [REQ_${requestId}] ${req.method} ${req.url}`);
    if (Object.keys(req.body).length) {
        console.log(`[REQ_${requestId}] Payload:`, JSON.stringify(req.body));
    }

    res.on('finish', () => {
        const duration = Date.now() - start;
        console.log(`[REQ_${requestId}] Completed ${res.statusCode} in ${duration}ms`);
    });
    next();
});

// Secure Media Proxy (Replacing public /uploads access)
app.get('/api/media/:filename', require('./src/controllers/ChatController').serveSecureMedia);

app.use(express.static(path.join(__dirname, 'public')));

// Health Check / Home Route
app.get('/', (req, res) => {
    res.send('🚀 GoGo Backend Server is Running Smoothly!');
});

// Admin Panel Route
app.get('/admin', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

// Routes
app.use('/api/user', require('./src/routes/userRoutes'));
app.use('/api/chat', require('./src/routes/chatRoutes'));
app.use('/api/admin', require('./src/routes/adminRoutes'));
app.use('/api/payment', require('./src/routes/paymentRoutes'));

const connectedUsers = new Map(); // socket.id -> phone
const phoneToSockets = new Map(); // phone -> Set of socket.ids

io.on('connection', (socket) => {
    console.log(`⚡ Connected: ${socket.id}`);
    analyticsService.trackEvent('connection');

    socket.on('set_online', (phone) => {
        if (!phone) return;
        socket.join(`user_${phone}`); // Personal room for global events
        connectedUsers.set(socket.id, phone);
        if (!phoneToSockets.has(phone)) phoneToSockets.set(phone, new Set());
        phoneToSockets.get(phone).add(socket.id);

        User.findOneAndUpdate({ phone }, { isOnline: true, lastSeen: new Date() }).then(user => {
            // Emit status change globally for discovery screen live updates
            io.emit('user_status_change', { phone, isOnline: true });
        }).catch(() => {});
    });

    socket.on('join_room', (roomId) => {
        socket.join(roomId);
        console.log(`🏠 ${socket.id} joined room: ${roomId}`);

        // Sync online status for the other person in room
        const phones = roomId.split('_');
        const myPhone = connectedUsers.get(socket.id);
        const otherPhone = phones.find(p => p !== myPhone);
        if (otherPhone) {
            const isOtherOnline = phoneToSockets.has(otherPhone) && phoneToSockets.get(otherPhone).size > 0;
            socket.emit('user_status_change', { phone: otherPhone, isOnline: isOtherOnline });

            // Notify the other person that I am online in this room
            if (myPhone) {
                socket.to(roomId).emit('user_status_change', { phone: myPhone, isOnline: true });
            }
        }
    });

    socket.on('send_message', async (data, callback) => {
        try {
            const [sender, receiver] = await Promise.all([
                User.findOne({ phone: data.senderPhone }, 'isPremium accountStatus isDeactivated'),
                User.findOne({ phone: data.receiverPhone }, 'accountStatus isDeactivated')
            ]);

            if (!sender || !sender.isPremium) {
                if (callback) callback({ success: false, message: "Premium required" });
                return;
            }

            if (sender.accountStatus === 'Deactivated' || sender.isDeactivated) {
                if (callback) callback({ success: false, message: "Account deactivated" });
                return;
            }

            if (receiver && (receiver.accountStatus === 'Deactivated' || receiver.isDeactivated)) {
                if (callback) callback({ success: false, message: "Recipient has deactivated their account" });
                return;
            }

            // --- AUTHORITATIVE BLOCK CHECK ---
            const blockRecord = await Block.findOne({
                $or: [
                    { blockerPhone: data.senderPhone, blockedPhone: data.receiverPhone },
                    { blockerPhone: data.receiverPhone, blockedPhone: data.senderPhone }
                ]
            });

            if (blockRecord) {
                console.log(`🚫 Message blocked: ${data.senderPhone} -> ${data.receiverPhone}`);
                if (callback) callback({
                    success: false,
                    message: "Chat blocked",
                    isBlocked: true,
                    blockerPhone: blockRecord.blockerPhone
                });
                return;
            }

            const users = [data.senderPhone, data.receiverPhone].sort();
            const roomId = users.join('_');
            const isReceiverOnline = phoneToSockets.has(data.receiverPhone);

            const tempId = new mongoose.Types.ObjectId();
            const timestamp = new Date();

            const responseData = {
                ...data,
                _id: tempId,
                roomId: roomId,
                timestamp: timestamp,
                isDelivered: isReceiverOnline
            };

            // --- STEP 1: INSTANT BROADCAST ---
            // Emit to the entire chat room AND receiver's personal room for inbox update
            io.to(roomId).to(`user_${data.receiverPhone}`).emit('receive_message', responseData);
            analyticsService.trackMessage();

            // Immediate ACK to sender
            if (callback) callback({ success: true, messageId: tempId, localId: data.localId });

            // --- STEP 2: BACKGROUND TASKS ---
            setImmediate(async () => {
                try {
                    const newMessage = new Message({
                        _id: tempId,
                        roomId,
                        senderPhone: data.senderPhone,
                        receiverPhone: data.receiverPhone,
                        message: data.message,
                        imageUrl: data.imageUrl,
                        audioUrl: data.audioUrl,
                        type: data.type || 'text',
                        isViewOnce: data.isViewOnce || false,
                        isDelivered: isReceiverOnline,
                        replyToId: data.replyToId,
                        replyText: data.replyText,
                        replyType: data.replyType,
                        timestamp: timestamp
                    });
                    await newMessage.save();

                    if (!isReceiverOnline) {
                        const receiverUser = await User.findOne({ phone: data.receiverPhone }, 'fcmToken');
                        if (receiverUser && receiverUser.fcmToken) {
                            notificationService.sendPushNotification(receiverUser.fcmToken, data.senderName || "New Message", data.message || "Sent a photo", {
                                senderPhone: String(data.senderPhone),
                                type: 'chat'
                            });
                        }
                    }
                } catch (err) { console.log("DB Error:", err); }
            });
        } catch (err) {
            console.error("Socket send_message error:", err);
            if (callback) callback({ success: false, message: "Server error" });
        }
    });

    socket.on('typing', async (data) => {
        try {
            const blockRecord = await Block.findOne({
                $or: [
                    { blockerPhone: data.myPhone, blockedPhone: data.otherPhone },
                    { blockerPhone: data.otherPhone, blockedPhone: data.myPhone }
                ]
            });
            if (blockRecord) return;

            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            socket.to(roomId).emit('display_typing', { phone: data.myPhone });
        } catch (e) {}
    });

    socket.on('stop_typing', async (data) => {
        try {
            const blockRecord = await Block.findOne({
                $or: [
                    { blockerPhone: data.myPhone, blockedPhone: data.otherPhone },
                    { blockerPhone: data.otherPhone, blockedPhone: data.myPhone }
                ]
            });
            if (blockRecord) return;

            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            socket.to(roomId).emit('hide_typing', { phone: data.myPhone });
        } catch (e) {}
    });

    socket.on('mark_opened', async (data) => {
        try {
            const blockRecord = await Block.findOne({
                $or: [
                    { blockerPhone: data.myPhone, blockedPhone: data.otherPhone },
                    { blockerPhone: data.otherPhone, blockedPhone: data.myPhone }
                ]
            });
            if (blockRecord) return;

            const message = await Message.findById(data.messageId);
            if (!message) return;

            message.isOpened = true;
            message.isDelivered = true;
            await message.save();

            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            io.to(roomId).emit('message_opened', {
                messageId: data.messageId,
                isViewOnce: message.isViewOnce
            });
        } catch (e) {
            console.error("Error in mark_opened:", e);
        }
    });

    socket.on('delete_message_for_everyone', async (data) => {
        try {
            const message = await Message.findById(data.messageId);
            if (message) {
                // Delete physical files if any
                const filesToDelete = [message.imageUrl, message.audioUrl];
                filesToDelete.forEach(url => {
                    if (url) {
                        try {
                            const fileName = url.split('/').pop();
                            const filePath = path.join(__dirname, 'uploads', fileName);
                            if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
                        } catch (fErr) {}
                    }
                });

                message.isDeletedForEveryone = true;
                message.message = "";
                message.imageUrl = null;
                message.audioUrl = null;
                await message.save();
            }

            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            io.to(roomId).emit('message_deleted_for_everyone', { messageId: data.messageId });
        } catch (e) {
            console.error("Error in delete_message_for_everyone:", e);
        }
    });

    socket.on('mark_chat_seen', async (data) => {
        try {
            const blockRecord = await Block.findOne({
                $or: [
                    { blockerPhone: data.myPhone, blockedPhone: data.otherPhone },
                    { blockerPhone: data.otherPhone, blockedPhone: data.myPhone }
                ]
            });
            if (blockRecord) return;

            const roomId = [data.myPhone, data.otherPhone].sort().join('_');
            // Do not auto-open view-once messages when just viewing the chat
            await Message.updateMany(
                { roomId, receiverPhone: data.myPhone, isOpened: false, isViewOnce: false },
                { isOpened: true, isDelivered: true }
            );
            socket.to(roomId).emit('chat_seen_update', { by: data.myPhone });
        } catch (e) {}
    });

    socket.on('block_user', async (data) => {
        try {
            const { blockerPhone, blockedPhone, reason } = data;
            await Block.findOneAndUpdate(
                { blockerPhone, blockedPhone },
                { reason, timestamp: new Date() },
                { upsert: true, new: true }
            );
            const roomId = [blockerPhone, blockedPhone].sort().join('_');
            const systemMsg = new Message({
                roomId,
                senderPhone: blockerPhone,
                receiverPhone: blockedPhone,
                message: `Blocked`,
                type: 'block_event'
            });
            await systemMsg.save();

            // Centralized Realtime Sync: Broadcast moderation status
            const syncData = {
                isBlocked: true,
                blockerPhone: blockerPhone,
                blockedPhone: blockedPhone,
                roomId: roomId
            };

            io.to(roomId).emit('moderation_state_updated', syncData);

            // Explicitly sync personal rooms as well for inbox awareness
            io.to(`user_${blockerPhone}`).to(`user_${blockedPhone}`).emit('moderation_state_updated', syncData);
            io.to(`user_${blockerPhone}`).to(`user_${blockedPhone}`).emit('receive_message', systemMsg);

            io.to(roomId).emit('receive_message', systemMsg);
        } catch (e) {
            console.error("Socket Block Error:", e);
        }
    });

    socket.on('unblock_user', async (data) => {
        try {
            const { blockerPhone, blockedPhone } = data;
            await Block.findOneAndDelete({ blockerPhone, blockedPhone });
            const roomId = [blockerPhone, blockedPhone].sort().join('_');

            const systemMsg = new Message({
                roomId,
                senderPhone: blockerPhone,
                receiverPhone: blockedPhone,
                message: `Unblocked`,
                type: 'unblock_event'
            });
            await systemMsg.save();

            // Centralized Realtime Sync: Broadcast moderation status
            const syncData = {
                isBlocked: false,
                blockerPhone: null,
                blockedPhone: blockedPhone,
                roomId: roomId
            };

            io.to(roomId).emit('moderation_state_updated', syncData);
            io.to(`user_${blockerPhone}`).to(`user_${blockedPhone}`).emit('moderation_state_updated', syncData);
            io.to(`user_${blockerPhone}`).to(`user_${blockedPhone}`).emit('receive_message', systemMsg);

            io.to(roomId).emit('receive_message', systemMsg);
        } catch (e) {
            console.error("Socket Unblock Error:", e);
        }
    });

    socket.on('delete_message', async (data) => {
        try {
            // For "Delete for me", we usually just acknowledge.
            // If you want it removed from DB entirely, use deleteOne.
            // For now, let's keep it simple as requested.
            console.log(`🗑️ Local delete requested for message: ${data.messageId}`);
        } catch (e) {
            console.error("Delete Error:", e);
        }
    });

    // --- WEBRTC SIGNALING ---

    socket.on('initiate_call', async (data) => {
        const { targetPhone, isVideo, callerName, callerPhone } = data;

        const [sender, receiver] = await Promise.all([
            User.findOne({ phone: callerPhone }, 'accountStatus isDeactivated'),
            User.findOne({ phone: targetPhone }, 'accountStatus isDeactivated')
        ]);

        if (sender && (sender.accountStatus === 'Deactivated' || sender.isDeactivated)) {
            socket.emit('call_error', { message: "Account deactivated" });
            return;
        }

        if (receiver && (receiver.accountStatus === 'Deactivated' || receiver.isDeactivated)) {
            socket.emit('call_error', { message: "Recipient has deactivated their account" });
            return;
        }

        console.log(`📞 Call initiated: ${callerPhone} -> ${targetPhone} (${isVideo ? 'Video' : 'Audio'})`);
        io.to(`user_${targetPhone}`).emit('incoming_call', {
            callerPhone,
            callerName,
            isVideo
        });
    });

    socket.on('call_ringing', (data) => {
        const { targetPhone } = data;
        io.to(`user_${targetPhone}`).emit('call_ringing', {});
    });

    socket.on('accept_call', (data) => {
        const { targetPhone } = data;
        io.to(`user_${targetPhone}`).emit('call_accepted', {});
    });

    socket.on('reject_call', (data) => {
        const { targetPhone } = data;
        io.to(`user_${targetPhone}`).emit('call_rejected', {});
    });

    socket.on('end_call', (data) => {
        const { targetPhone } = data;
        io.to(`user_${targetPhone}`).emit('call_ended', {});
    });

    socket.on('call_busy', (data) => {
        const { targetPhone } = data;
        io.to(`user_${targetPhone}`).emit('call_busy', {});
    });

    socket.on('sdp_offer', (data) => {
        const { targetPhone, offer } = data;
        io.to(`user_${targetPhone}`).emit('sdp_offer', { offer });
    });

    socket.on('sdp_answer', (data) => {
        const { targetPhone, answer } = data;
        io.to(`user_${targetPhone}`).emit('sdp_answer', { answer });
    });

    socket.on('ice_candidate', (data) => {
        const { targetPhone, candidate } = data;
        io.to(`user_${targetPhone}`).emit('ice_candidate', { candidate });
    });

    socket.on('call_state_sync', (data) => {
        const { targetPhone, isMuted, isVideoOff } = data;
        io.to(`user_${targetPhone}`).emit('call_state_sync', { isMuted, isVideoOff });
    });

    socket.on('log_call', async (data) => {
        try {
            const { senderPhone, receiverPhone, callType, duration, status } = data;
            console.log(`📝 Log Call: ${senderPhone} -> ${receiverPhone} | ${callType} | ${duration}s | ${status}`);

            const callMessage = new Message({
                roomId: [senderPhone, receiverPhone].sort().join('_'),
                senderPhone,
                receiverPhone,
                message: `${callType === 'video' ? 'Video' : 'Audio'} Call (${status})`,
                type: 'call_log',
                timestamp: new Date(),
                metadata: { duration, status, callType }
            });
            await callMessage.save();

            // Emit to both users for inbox update
            const roomId = [senderPhone, receiverPhone].sort().join('_');
            io.to(roomId).to(`user_${senderPhone}`).to(`user_${receiverPhone}`).emit('receive_message', callMessage);
        } catch (e) {
            console.error("Log Call Error:", e);
        }
    });

    // --- NEW RANDOM VIDEO SYSTEM (FINAL PRODUCTION PLAN) ---
    // Separate from normal 1-to-1 calls

    socket.on('random_find_partner', (data) => {
        randomMatchController.findPartner(io, socket, data);
    });

    socket.on('random_leave_room', (data) => {
        randomMatchController.leaveRoom(io, socket, data.userId);
    });

    socket.on('next_random_partner', (data) => {
        randomMatchController.handleNextPartner(io, socket, data);
    });

    socket.on('random_offer', (data) => {
        randomMatchController.handleSignaling(io, socket, data, 'offer');
    });

    socket.on('random_answer', (data) => {
        randomMatchController.handleSignaling(io, socket, data, 'answer');
    });

    socket.on('random_candidate', (data) => {
        randomMatchController.handleSignaling(io, socket, data, 'candidate');
    });

    socket.on('random_call_state_sync', (data) => {
        randomMatchController.handleSignaling(io, socket, data, 'call_state_sync');
    });

    socket.on('random_partner_blocked', (data) => {
        randomMatchController.handleBlock(io, socket, data);
    });

    socket.on('disconnecting', () => {
        const phone = connectedUsers.get(socket.id);
        if (!phone) return;

        const sockets = phoneToSockets.get(phone);
        if (sockets && sockets.size === 1) {
            // This is the last socket for this user
            const rooms = Array.from(socket.rooms);
            rooms.forEach(room => {
                if (room !== socket.id) {
                    socket.to(room).emit('user_status_change', { phone, isOnline: false });
                }
            });
        }
    });

    socket.on('disconnect', () => {
        analyticsService.trackEvent('disconnect');
        const phone = connectedUsers.get(socket.id);
        if (phone) {
            // Cleanup random room on disconnect (Final Production Plan)
            randomMatchController.leaveRoom(io, socket, phone);

            const sockets = phoneToSockets.get(phone);
            if (sockets) {
                sockets.delete(socket.id);
                if (sockets.size === 0) {
                    phoneToSockets.delete(phone);
                    User.findOneAndUpdate({ phone }, { isOnline: false, lastSeen: new Date() }).then(() => {
                        io.emit('user_status_change', { phone, isOnline: false });
                    }).catch(() => {});
                }
            }
            connectedUsers.delete(socket.id);
        }
    });
});

server.listen(80, '0.0.0.0', () => console.log(`🚀 Realtime Server on 80`));
