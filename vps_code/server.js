require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const http = require('http');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const connectDB = require('./src/config/db');
const { createClient } = require('redis');

// Redis Setup for High-Speed Presence & Caching
const redisClient = createClient({
    socket: {
        host: '127.0.0.1',
        port: 6379,
        reconnectStrategy: (retries) => Math.min(retries * 500, 2000)
    }
});

// Pub/Sub Clients for Real-time Indicators (Optimized)
const pubClient = redisClient.duplicate();
const subClient = redisClient.duplicate();

redisClient.on('error', (err) => console.error('❌ Redis Client Error:', err.message));
redisClient.on('ready', async () => {
    console.log('🚀 Redis Connected: High-Performance Engine Active');
    try {
        await redisClient.del('online_users'); // Fresh start
        // CRITICAL: Also sync MongoDB on startup to prevent "Ghost" online users after a crash
        // Using lazy require to avoid circular dependency
        const User = require('./src/models/User');
        await User.updateMany({}, { isOnline: false });
        console.log('✅ MongoDB Online Status Reset');
    } catch (err) {
        console.error('❌ Startup Sync Error:', err.message);
    }
});

(async () => {
    try {
        await Promise.all([
            redisClient.connect(),
            pubClient.connect(),
            subClient.connect()
        ]);
    } catch (err) {
        console.error("❌ Redis Initial Connection Failed:", err.message);
    }
})();

// Subscribe to Typing Channel (Scalability)
subClient.subscribe('typing_events', (message) => {
    const data = JSON.parse(message);
    io.to(`user_${data.other}`).emit(data.event, { phone: data.from });
});

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
const { updateConversationSummary, resetUnreadCount, queueStatusUpdate } = require('./src/utils/chatUtils');

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

const io = new Server(server, {
    cors: { origin: "*" },
    pingTimeout: 60000, // 60s timeout for stability on mobile networks
    pingInterval: 25000,
    transports: ['websocket'],
    maxHttpBufferSize: 1e6 // 1MB limit for messages
});

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

connectDB().then(() => {
    console.log("🚀 Database connected.");
}).catch(err => {
    console.error("❌ Database connection error:", err);
});
analyticsService.init(io, redisClient);
revenueService.init(io, redisClient);

setInterval(() => { randomMatchController.performGlobalCleanup(); }, 120000);

app.set('socketio', io);
app.set('redis', redisClient);
app.set('redisPub', pubClient);
app.use(cors());
app.use(express.json());

// 100% FIX: Direct Route for OTP
const UserController = require('./src/controllers/UserController');
app.post('/api/user/send-otp', UserController.sendOTP);
app.post('/api/user/login', UserController.login);

// Global Request Logger (Development Only)
if (process.env.NODE_ENV !== 'production') {
    app.use((req, res, next) => {
        if (!req.url.includes('/media/')) {
            console.log(`🌐 [${new Date().toISOString()}] ${req.method} ${req.url}`);
        }
        next();
    });
}

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

// --- GLOBAL ERROR HANDLING (PREVENTS CORRUPTION) ---
process.on('uncaughtException', (err) => {
    console.error('❌ FATAL: Uncaught Exception:', err);
    process.exit(1); // Exit and let PM2 restart for a clean state
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('❌ FATAL: Unhandled Rejection at:', promise, 'reason:', reason);
    process.exit(1); // Exit and let PM2 restart for a clean state
});

const phoneToSockets = new Map();
io.onlineUsers = phoneToSockets; // Make it accessible to controllers

io.on('connection', (socket) => {
    const myPhone = socket.userPhone;

    if (socket.decoded?.role) {
        socket.join('admin');
        console.log(`👨‍💼 Admin connected: ${socket.decoded.username}`);
        io.to('admin').emit('admin_live_event', { type: 'ADMIN_JOIN', label: 'Admin Logged In', user: socket.decoded.username });
        if (socket.decoded.username) {
            redisClient.sAdd('active_admins', socket.decoded.username).catch(() => {});
        }
    }

    if (myPhone) {
        socket.join(`user_${myPhone}`);
        if (!phoneToSockets.has(myPhone)) {
            phoneToSockets.set(myPhone, new Set());
            io.to('admin').emit('admin_live_event', { type: 'USER_JOIN', label: 'User Online', phone: myPhone });
            analyticsService.trackEvent('app_open', myPhone);
        }
        phoneToSockets.get(myPhone).add(socket.id);
    }

    socket.on('set_online', async (phone) => {
        const normalized = myPhone;
        if (!normalized) return;

        try {
            // Track in Redis for 100% real-time status (Removing isComplete check for accuracy)
            await redisClient.sAdd('online_users', normalized);
            console.log(`[Redis] User Online: ${normalized}`);

            await User.findOneAndUpdate(phoneQuery(normalized), { isOnline: true, lastSeen: new Date() });

            socket.broadcast.emit('user_status_change', { phone: normalized, isOnline: true });

            const phoneVariations = [normalized, `+91${normalized}`, `91${normalized}`];
            const result = await Message.updateMany({
                receiverPhone: { $in: phoneVariations },
                isDelivered: false
            }, { isDelivered: true });

            if (result.modifiedCount > 0) {
                io.to(`user_${normalized}`).emit('pending_messages_delivered', { phone: normalized });
                // Optimization: Instead of distinct query and massive loop, broadcast a single event
                // Senders will receive this and update their UI if they are currently chatting with this user.
                socket.broadcast.emit('global_delivery_update', { receiverPhone: normalized });
            }
        } catch (e) {
            console.error("set_online error:", e);
        }
    });

    socket.on('typing', (data) => {
        const other = normalizePhone(data.otherPhone);
        if (other) {
            pubClient.publish('typing_events', JSON.stringify({
                event: 'display_typing',
                from: myPhone,
                other: other
            }));
        }
    });

    socket.on('stop_typing', (data) => {
        const other = normalizePhone(data.otherPhone);
        if (other) {
            pubClient.publish('typing_events', JSON.stringify({
                event: 'hide_typing',
                from: myPhone,
                other: other
            }));
        }
    });

    // --- CALLING SYSTEM ---
    socket.on('initiate_call', async (data) => {
        const other = normalizePhone(data.targetPhone || data.receiverPhone);
        if (other) {
            // SECURITY: Check if either user has blocked the other
            const block = await Block.findOne({
                $or: [
                    { blockerPhone: myPhone, blockedPhone: other },
                    { blockerPhone: other, blockedPhone: myPhone }
                ]
            });

            if (block) {
                console.warn(`🚫 Blocked call attempt: ${myPhone} -> ${other}`);
                return; // Silently ignore or emit an error if needed
            }

            const roomId = getRoomId(myPhone, other);
            analyticsService.trackCallStart(roomId);
            io.to(`user_${other}`).emit('incoming_call', { callerPhone: myPhone, callerName: data.callerName, isVideo: data.isVideo });
        }
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
        if (other) {
            analyticsService.trackCallEnd(getRoomId(myPhone, other));
            io.to(`user_${other}`).emit('call_ended', { by: myPhone });
        }
    });

    socket.on('log_call', async (data) => {
        try {
            const sender = normalizePhone(data.senderPhone);
            const receiver = normalizePhone(data.receiverPhone);
            const roomId = getRoomId(sender, receiver);

            const callLog = new Message({
                roomId,
                senderPhone: sender,
                receiverPhone: receiver,
                type: 'call_log',
                message: data.callType === 'video' ? 'Video Call' : 'Voice Call',
                metadata: {
                    callType: data.callType,
                    duration: data.duration,
                    status: data.status
                },
                timestamp: new Date() // Always use server time for consistent sorting
            });

            await callLog.save();
            updateConversationSummary(callLog);

            const callLogObj = callLog.toObject();
            io.to(`user_${sender}`).emit('receive_message', callLogObj);
            io.to(`user_${receiver}`).emit('receive_message', callLogObj);
        } catch (e) {
            console.error("log_call error:", e);
        }
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

    socket.on('mark_delivered', async (data) => {
        try {
            const { messageId, localId } = data;
            if (!messageId) return;

            // Ultra Pro: Queue for batch DB update and emit instantly via socket
            queueStatusUpdate(messageId, 'delivered');

            const msg = await Message.findById(messageId, 'senderPhone receiverPhone localId').lean();
            if (msg) {
                io.to(`user_${normalizePhone(msg.senderPhone)}`).emit('message_delivered', {
                    messageId: messageId,
                    localId: localId || msg.localId,
                    roomId: getRoomId(msg.senderPhone, msg.receiverPhone)
                });
            }
        } catch (e) {
            console.error("mark_delivered error:", e);
        }
    });

    socket.on('mark_opened', async (data) => {
        try {
            const { messageId, otherPhone } = data;
            if (!messageId) return;

            // Ultra Pro: Queue for batch DB update
            queueStatusUpdate(messageId, 'seen');

            const msg = await Message.findById(messageId);
            // Security: Ensure only the receiver can mark a message as opened
            if (msg && normalizePhone(msg.receiverPhone) === myPhone) {
                // View Once cleanup can stay individual as it involves nulling fields
                if (msg.isViewOnce) {
                    msg.isOpened = true;
                    msg.isDelivered = true;
                    msg.imageUrl = null;
                    msg.audioUrl = null;
                    await msg.save();
                }

                const roomId = getRoomId(myPhone, otherPhone);
                const statusData = {
                    messageId,
                    roomId,
                    senderPhone: msg.senderPhone,
                    receiverPhone: msg.receiverPhone
                };
                io.to(roomId).emit('message_opened', statusData);
                io.to(`user_${normalizePhone(msg.senderPhone)}`).emit('message_opened', statusData);
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
                // Call logs cannot be deleted for everyone
                if (msg.type === 'call_log') return;

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

            io.to(roomId).emit('moderation_state_updated', { roomId, isBlocked: true, blockerPhone: b1, blockedPhone: b2 });
            io.to(roomId).emit('receive_message', eventMsg);

            // Guarantee blocker sees it too in real-time
            io.to(`user_${b1}`).emit('receive_message', eventMsg);
            io.to(`user_${b1}`).emit('moderation_state_updated', { roomId, isBlocked: true, blockerPhone: b1, blockedPhone: b2 });
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

            io.to(roomId).emit('moderation_state_updated', { roomId, isBlocked: false, blockerPhone: b1, blockedPhone: b2 });
            io.to(roomId).emit('receive_message', eventMsg);

            // Guarantee unblocker sees it too in real-time
            io.to(`user_${b1}`).emit('receive_message', eventMsg);
            io.to(`user_${b1}`).emit('moderation_state_updated', { roomId, isBlocked: false, blockerPhone: b1, blockedPhone: b2 });
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

            // SECURITY: Check if either user has blocked the other
            const block = await Block.findOne({
                $or: [
                    { blockerPhone: myPhone, blockedPhone: receiver },
                    { blockerPhone: receiver, blockedPhone: myPhone }
                ]
            });

            if (block) {
                console.warn(`🚫 Blocked message attempt: ${myPhone} -> ${receiver}`);
                return callback && callback({
                    success: false,
                    message: "You cannot send messages to this user."
                });
            }

            const isReceiverOnline = phoneToSockets.has(receiver) && phoneToSockets.get(receiver).size > 0;

            const tempId = new mongoose.Types.ObjectId();
            const timestamp = new Date();

            const responseData = { ...data, _id: tempId, senderPhone: myPhone, receiverPhone: receiver, roomId, timestamp, isDelivered: isReceiverOnline };

            // Sequential Flow Fix: Use socket.to(roomId) instead of io.to(roomId)
            // so the sender doesn't receive their own message back.
            // Receiver will get it via room if they are in it, otherwise via private channel.
            socket.to(roomId).emit('receive_message', responseData);

            const receiverRoom = io.sockets.adapter.rooms.get(roomId);
            const receiverInRoom = receiverRoom && Array.from(receiverRoom).some(sid => {
                const s = io.sockets.sockets.get(sid);
                return s && s.userPhone === receiver;
            });

            if (!receiverInRoom) {
                io.to(`user_${receiver}`).emit('receive_message', responseData);
            }

            io.to(`user_${receiver}`).emit('hide_typing', { phone: myPhone });

            if (isReceiverOnline) io.to(`user_${myPhone}`).emit('message_delivered', { messageId: tempId.toString(), localId: data.localId, roomId });
            if (callback) callback({ success: true, messageId: tempId.toString(), localId: data.localId });

            analyticsService.trackMessage();

            const newMessage = new Message({
                _id: tempId, roomId, senderPhone: myPhone, receiverPhone: receiver,
                localId: data.localId, // Save client's local ID
                message: data.message, imageUrl: data.imageUrl, audioUrl: data.audioUrl,
                type: data.type || 'text', isViewOnce: data.isViewOnce || false,
                isDelivered: isReceiverOnline, replyToId: data.replyToId, replyText: data.replyText, replyType: data.replyType, timestamp
            });
            await newMessage.save();
            await User.updateOne({ phone: myPhone }, { $inc: { chatCount: 1 } });
            updateConversationSummary(newMessage);

            // --- SEND PUSH NOTIFICATION (BACKGROUND) ---
            try {
                const receiverUser = await User.findOne(phoneQuery(receiver), 'fcmToken').lean();
                if (receiverUser?.fcmToken) {
                    const senderUser = await User.findOne(phoneQuery(myPhone), 'name position').lean();
                    const senderName = senderUser?.name || "Someone";

                    let body = data.message;
                    if (data.type === 'image') body = "📷 Sent an image";
                    else if (data.type === 'audio') body = "🎵 Sent a voice message";
                    else if (data.type === 'video') body = "🎥 Sent a video";

                    // Fire and forget (don't await) to keep socket event loop fast
                    notificationService.sendPushNotification(
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
                    ).then(result => {
                        if (result && result.isInvalidToken) {
                            User.updateOne({ _id: receiverUser._id }, { $unset: { fcmToken: 1 } }).exec();
                        }
                    }).catch(e => {});
                }
            } catch (notifyErr) {
                // Silent catch for notification errors
            }
        } catch (err) {
            console.error("SEND_MESSAGE_ERROR:", err);
            if (callback) callback({ success: false });
        }
    });

    socket.on('mark_chat_seen', async (data) => {
        try {
            const other = normalize(data.otherPhone);
            const m = myPhone;
            const o = other;

            const possibleRoomIds = [
                [m, o].sort().join('_'),
                m + '_' + o,
                o + '_' + m,
                `+91${m}_+91${o}`,
                `+91${o}_+91${m}`,
                `+91${m}_${o}`,
                `${m}_+91${o}`,
                `+91${o}_${m}`,
                `${o}_+91${m}`
            ];

            const phoneVariations = [myPhone, `+91${myPhone}`, `91${myPhone}`];

            // SECURITY FIX: Only mark normal messages as 'Opened' (Seen).
            await Message.updateMany(
                {
                    roomId: { $in: possibleRoomIds },
                    receiverPhone: { $in: phoneVariations },
                    isOpened: false,
                    isViewOnce: false
                },
                { isOpened: true, isDelivered: true }
            );

            // For View Once, just ensure they are marked as Delivered
            await Message.updateMany(
                {
                    roomId: { $in: possibleRoomIds },
                    receiverPhone: { $in: phoneVariations },
                    isDelivered: false,
                    isViewOnce: true
                },
                { isDelivered: true }
            );

            await resetUnreadCount(myPhone, other);

            const roomId = [m, o].sort().join('_');

            // Optimization: Prevent duplicate 'chat_seen_update' emissions
            const room = io.sockets.adapter.rooms.get(roomId);
            const otherInRoom = room && Array.from(room).some(sid => {
                const s = io.sockets.sockets.get(sid);
                return s && s.userPhone === other;
            });

            if (otherInRoom) {
                socket.to(roomId).emit('chat_seen_update', { by: myPhone, roomId });
            } else {
                io.to(`user_${other}`).emit('chat_seen_update', { by: myPhone, roomId });
            }

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

            // Also notify the other user that we are active in the room
            // This helps with immediate delivery/seen synchronization
            io.to(`user_${other}`).emit('chat_status_update', { roomId: cleanRoomId, phone: myPhone, status: 'active' });
        }
    });

    // --- RANDOM MATCHING SYSTEM ---
    socket.on('find_partner', (data) => randomMatchController.findPartner(io, socket, data));
    socket.on('leave_random_room', () => randomMatchController.leaveRoom(io, socket));
    socket.on('next_partner', (data) => randomMatchController.handleNextPartner(io, socket, data));
    socket.on('random_offer', (data, cb) => randomMatchController.handleSignaling(io, socket, data, 'offer', cb));
    socket.on('random_answer', (data, cb) => randomMatchController.handleSignaling(io, socket, data, 'answer', cb));
    socket.on('random_candidate', (data, cb) => randomMatchController.handleSignaling(io, socket, data, 'candidate', cb));
    socket.on('random_message', (data, cb) => randomMatchController.handleSignaling(io, socket, data, 'message', cb));
    socket.on('random_hi', (data, cb) => randomMatchController.handleSignaling(io, socket, data, 'hi', cb));
    socket.on('random_block', (data) => randomMatchController.handleBlock(io, socket, data));

    socket.on('disconnect', () => {
        if (socket.decoded?.role && socket.decoded.username) {
            redisClient.sRem('active_admins', socket.decoded.username).catch(() => {});
        }
        if (myPhone) {
            // Clean up random rooms immediately on disconnect
            randomMatchController.leaveRoom(io, socket);

            const sockets = phoneToSockets.get(myPhone);
            if (sockets) {
                sockets.delete(socket.id);
                if (sockets.size === 0) {
                    phoneToSockets.delete(myPhone);
                    io.to('admin').emit('admin_live_event', { type: 'USER_LEAVE', label: 'User Offline', phone: myPhone });

                    // CRITICAL: Remove from Redis presence set
                    redisClient.sRem('online_users', myPhone).then(() => {
                        console.log(`[Redis] User Offline: ${myPhone}`);
                    }).catch(() => {});

                    // CRITICAL: Robust status update on disconnect
                    User.updateMany(phoneQuery(myPhone), { isOnline: false }).then(() => {
                        io.emit('user_status_change', { phone: myPhone, isOnline: false });
                    }).catch(e => console.error("Disconnect status update error:", e));
                }
            }
        }
    });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server on ${PORT}`);

    // --- GHOST USER CLEANUP TASK (Runs every 5 minutes) ---
    setInterval(async () => {
        try {
            const onlineInDB = await User.find({ isOnline: true }, 'phone').lean();
            for (const user of onlineInDB) {
                // If user is online in DB but NOT in our local socket map
                if (!phoneToSockets.has(user.phone)) {
                    await User.updateOne({ _id: user._id }, { isOnline: false });
                    await redisClient.sRem('online_users', user.phone);
                    io.emit('user_status_change', { phone: user.phone, isOnline: false });
                    console.log(`🧹 Ghost Cleanup: Marked ${user.phone} as Offline`);
                }
            }
        } catch (err) {
            console.error("❌ Cleanup Error:", err.message);
        }
    }, 5 * 60 * 1000); // 5 Minutes
});
