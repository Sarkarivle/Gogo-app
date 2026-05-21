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

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: "*" },
    pingTimeout: 20000,
    pingInterval: 5000,
    transports: ['websocket']
});

connectDB();

app.set('socketio', io); // Set socket.io instance to app for global access

app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
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

    socket.on('set_online', (phone) => {
        if (!phone) return;
        connectedUsers.set(socket.id, phone);
        if (!phoneToSockets.has(phone)) phoneToSockets.set(phone, new Set());
        phoneToSockets.get(phone).add(socket.id);

        User.findOneAndUpdate({ phone }, { isOnline: true, lastSeen: new Date() }).then(user => {
            if (user && !user.isOnline) io.emit('user_status_change', { phone, isOnline: true });
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
        }
    });

    socket.on('send_message', async (data, callback) => {
        try {
            const sender = await User.findOne({ phone: data.senderPhone });
            if (!sender || !sender.isPremium) {
                if (callback) callback({ success: false, message: "Premium required" });
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
            // Emit to the entire room (including sender) for sync
            io.to(roomId).emit('receive_message', responseData);

            // Immediate ACK to sender to stop the "loading wheel"
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

    socket.on('typing', (data) => {
        const roomId = [data.myPhone, data.otherPhone].sort().join('_');
        socket.to(roomId).emit('display_typing', { phone: data.myPhone });
    });

    socket.on('stop_typing', (data) => {
        const roomId = [data.myPhone, data.otherPhone].sort().join('_');
        socket.to(roomId).emit('hide_typing', { phone: data.myPhone });
    });

    socket.on('mark_opened', async (data) => {
        try {
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

            // Also send to all individual sockets of the blocked user (in case they aren't in the room)
            const blockedUserSockets = phoneToSockets.get(blockedPhone);
            if (blockedUserSockets) {
                blockedUserSockets.forEach(sId => io.to(sId).emit('moderation_state_updated', syncData));
            }

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

            // Also send to all individual sockets of the blocked user
            const blockedUserSockets = phoneToSockets.get(blockedPhone);
            if (blockedUserSockets) {
                blockedUserSockets.forEach(sId => io.to(sId).emit('moderation_state_updated', syncData));
            }

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

    socket.on('disconnect', () => {
        const phone = connectedUsers.get(socket.id);
        if (phone) {
            const sockets = phoneToSockets.get(phone);
            if (sockets) {
                sockets.delete(socket.id);
                if (sockets.size === 0) {
                    phoneToSockets.delete(phone);
                    User.findOneAndUpdate({ phone }, { isOnline: false, lastSeen: new Date() }).then(() => {
                        io.emit('user_status_change', { phone, isOnline: false });
                    });
                }
            }
            connectedUsers.delete(socket.id);
        }
    });
});

server.listen(5000, '0.0.0.0', () => console.log(`🚀 Realtime Server on 5000`));
