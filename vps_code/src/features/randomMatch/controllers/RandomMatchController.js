const RandomRoom = require('../models/RandomRoom');
const Block = require('../../chat/models/Block');
const { normalize } = require('../../../shared/utils/phoneUtils');
const crypto = require('crypto');

/**
 * EPHEMERAL (TEMPORARY) MATCH CONTROLLER
 * Logic: MongoDB is ONLY for waiting. Active calls live in RAM.
 * Result: Zero Ghost Rooms, Zero Lag, Zero Loops.
 */

exports.findPartner = async (io, socket, data) => {
    const userId = socket.userPhone;
    if (!userId) {
        socket.emit('random_reset', { message: "Auth required" });
        return;
    }

    const redis = io.redis || (socket.request.app && socket.request.app.get('redis'));

    // 1. CHECK ONBOARDING STATUS
    const User = require('../../users/models/User');
    const user = await User.findOne({ phone: userId }, 'hasCompletedOnboarding').lean();
    if (!user || !user.hasCompletedOnboarding) {
        socket.emit('random_reset', { message: "Please complete your profile onboarding first" });
        return;
    }

    // 2. CLEAR SOCKET MEMORY IMMEDIATELY
    socket.partnerSocketId = null;
    socket.currentRoomId = null;
    socket.emit('random_search_started');

    try {
        // --- RATE LIMITING: Prevents Spam Clicking ---
        if (redis) {
            const rateKey = `rate:match:${userId}`;
            const count = await redis.incr(rateKey);
            if (count === 1) await redis.expire(rateKey, 10); // 10s window
            if (count > 5) { // Max 5 clicks per 10s
                return socket.emit('random_reset', { message: "Too many attempts. Please wait 10 seconds." });
            }
        }

        // --- REDIS-POWERED MATCHING QUEUE ---
        if (redis) {
            // Remove user from queue if already there (Reset)
            await redis.lRem('match_queue', 0, userId);

            // Fetch the next person waiting
            const partnerId = await redis.lPop('match_queue');

            if (partnerId && partnerId !== userId) {
                // MATCH FOUND IN REDIS!
                const partnerSocketId = (await redis.get(`socket:${partnerId}`));
                const partnerSocket = io.sockets.sockets.get(partnerSocketId);

                if (partnerSocket && partnerSocket.connected) {
                    const roomId = `rnd_${crypto.randomBytes(3).toString('hex')}_${userId.slice(-4)}`;

                    socket.partnerSocketId = partnerSocket.id;
                    socket.currentRoomId = roomId;
                    partnerSocket.partnerSocketId = socket.id;
                    partnerSocket.currentRoomId = roomId;

                    partnerSocket.join(roomId);
                    socket.join(roomId);

                    const payload = { roomId, ts: Date.now() };
                    io.to(partnerSocket.id).emit('random_match_found', { ...payload, partnerId: userId, role: 'receiver' });
                    socket.emit('random_match_found', { ...payload, partnerId: partnerId, role: 'caller' });

                    console.log(`[RedisMatch] Match: ${userId} <-> ${partnerId}`);
                    return;
                }
            }

            // NO MATCH -> JOIN QUEUE
            await redis.rPush('match_queue', userId);
            await redis.setEx(`socket:${userId}`, 300, socket.id);
            console.log(`[RedisMatch] User ${userId} joined queue`);
            return;
        }

        // FALLBACK TO MONGODB (If Redis fails)
        await RandomRoom.deleteMany({ hostId: userId }).exec();

        const lastPartnerId = data?.lastPartnerId ? normalize(data.lastPartnerId) : null;

        const blocks = await Block.find({
            $or: [{ blockerPhone: userId }, { blockedPhone: userId }]
        }, 'blockerPhone blockedPhone').lean();

        const excludedPhones = blocks.map(b => {
            const b1 = normalize(b.blockerPhone);
            const b2 = normalize(b.blockedPhone);
            return b1 === userId ? b2 : b1;
        });
        if (lastPartnerId) excludedPhones.push(lastPartnerId);

        let roomToJoin = null;
        let hostSocket = null;

        for (let i = 0; i < 3; i++) {
            roomToJoin = await RandomRoom.findOneAndDelete({
                status: 'waiting',
                hostId: { $ne: userId, $nin: excludedPhones }
            }).sort({ createdAt: 1 }).lean();

            if (!roomToJoin) break;

            hostSocket = io.sockets.sockets.get(roomToJoin.socketIds.host);
            if (hostSocket && hostSocket.connected) {
                break;
            } else {
                roomToJoin = null;
                hostSocket = null;
            }
        }

        if (roomToJoin && hostSocket) {
            const roomId = roomToJoin.roomId;
            socket.partnerSocketId = hostSocket.id;
            socket.currentRoomId = roomId;
            hostSocket.partnerSocketId = socket.id;
            hostSocket.currentRoomId = roomId;

            hostSocket.join(roomId);
            socket.join(roomId);

            const payload = { roomId, ts: Date.now() };
            io.to(hostSocket.id).emit('random_match_found', { ...payload, partnerId: userId, role: 'receiver' });
            socket.emit('random_match_found', { ...payload, partnerId: roomToJoin.hostId, role: 'caller' });
            return;
        }

        const roomId = `rnd_${crypto.randomBytes(3).toString('hex')}_${userId.slice(-4)}`;
        const newRoom = new RandomRoom({
            roomId, hostId: userId, socketIds: { host: socket.id }, status: 'waiting'
        });

        await newRoom.save();
        socket.currentRoomId = roomId;
        socket.emit('random_room_created', { roomId });

    } catch (err) {
        console.error("[EphemeralMatch] Error in findPartner:", err);
        socket.emit('random_reset', { error: "Matching service temporarily unavailable" });
    }
};

/**
 * ULTRA-FAST SIGNALING (No DB Hits)
 * Designed to NEVER hang UI buttons
 */
exports.handleSignaling = (io, socket, data, type, ack) => {
    // 1. SMART CALLBACK DETECTION: Unblocks the UI button instantly
    const callback = (typeof data === 'function') ? data : (typeof ack === 'function' ? ack : null);
    const actualData = (typeof data === 'object' && data !== null) ? data : {};

    if (callback) callback({ success: true, ts: Date.now() });

    // 2. ROUTING: Use RAM-based IDs for 0.1ms delivery
    const target = socket.partnerSocketId || actualData.partnerSocketId || actualData.roomId;

    if (target) {
        socket.to(target).emit(`random_${type}`, {
            ...actualData,
            fromSocketId: socket.id,
            ts: Date.now()
        });
    } else if (actualData.partnerId) {
        // Fallback to phone-based channel if socket info is missing
        io.to(`user_${normalize(actualData.partnerId)}`).emit(`random_${type}`, {
            ...actualData,
            fromSocketId: socket.id,
            ts: Date.now()
        });
    }
};

exports.leaveRoom = async (io, socket, notifyPartner = true) => {
    try {
        const userId = socket.userPhone;
        const rid = socket.currentRoomId;
        const pid = socket.partnerSocketId;

        const redis = io.redis || (socket.request.app && socket.request.app.get('redis'));
        if (redis && userId) {
            await redis.lRem('match_queue', 0, userId);
            await redis.del(`socket:${userId}`);
        }

        // 1. INSTANT RAM WIPE & PARTNER NOTIFICATION
        if (pid) {
            if (notifyPartner) {
                io.to(pid).emit('random_partner_left', { autoSearch: true });
            }

            const partnerSocket = io.sockets.sockets.get(pid);
            if (partnerSocket) {
                // Partner's memory cleanup
                partnerSocket.partnerSocketId = null;
                partnerSocket.currentRoomId = null;
                if (rid) partnerSocket.leave(rid);
            }
        }

        // 2. SELF CLEANUP (RAM)
        socket.partnerSocketId = null;
        socket.currentRoomId = null;
        if (rid) socket.leave(rid);

        // 3. DATABASE PURGE
        // Cleanup where user was host OR guest OR the room ID specifically
        if (userId || rid) {
            RandomRoom.deleteMany({
                $or: [
                    { hostId: userId },
                    { roomId: rid }
                ]
            }).exec().catch(e => console.error("[EphemeralMatch] Cleanup DB Error:", e));
        }

        if (userId) console.log(`[EphemeralMatch] Cleanup completed for ${userId}`);
    } catch (err) {
        console.error("[EphemeralMatch] leaveRoom Error:", err);
    }
};

exports.handleCancelSearch = async (io, socket) => {
    socket.emit('random_search_cancelled');
    exports.leaveRoom(io, socket, false);
};

exports.handleNextPartner = async (io, socket) => {
    socket.emit('random_searching_again');
    exports.leaveRoom(io, socket, true);
};

exports.handleBlock = async (io, socket, data) => {
    if (!data || !data.partnerId) return;

    Block.findOneAndUpdate(
        { blockerPhone: socket.userPhone, blockedPhone: normalize(data.partnerId) },
        { reason: "Blocked", timestamp: new Date() },
        { upsert: true }
    ).exec();

    exports.leaveRoom(io, socket, true);
};

exports.performGlobalCleanup = async () => {
    try {
        // Clean stale waiting rooms only
        const expiry = new Date(Date.now() - 2 * 60 * 1000);
        await RandomRoom.deleteMany({ createdAt: { $lt: expiry }, status: 'waiting' });
    } catch (e) {}
};
