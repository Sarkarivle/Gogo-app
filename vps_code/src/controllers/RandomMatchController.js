const RandomRoom = require('../models/RandomRoom');
const Block = require('../models/Block');
const { normalize } = require('../utils/phoneUtils');
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

    // 1. CHECK ONBOARDING STATUS
    const User = require('../models/User');
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
        // 2. CLEANUP DB (Atomic cleanup before searching)
        await RandomRoom.deleteMany({ hostId: userId }).exec();

        const lastPartnerId = data?.lastPartnerId ? normalize(data.lastPartnerId) : null;

        // 3. FETCH EXCLUSIONS (Blocked users)
        const blocks = await Block.find({
            $or: [{ blockerPhone: userId }, { blockedPhone: userId }]
        }, 'blockerPhone blockedPhone').lean();

        const excludedPhones = blocks.map(b => {
            const b1 = normalize(b.blockerPhone);
            const b2 = normalize(b.blockedPhone);
            return b1 === userId ? b2 : b1;
        });
        if (lastPartnerId) excludedPhones.push(lastPartnerId);

        // 4. FIND & CONSUME (The Temporary Logic)
        let roomToJoin = null;
        let hostSocket = null;

        // Try up to 3 times to find a room with a valid connected host
        // This prevents the "stuck" feeling when multiple stale entries exist in DB
        for (let i = 0; i < 3; i++) {
            roomToJoin = await RandomRoom.findOneAndDelete({
                status: 'waiting',
                hostId: { $ne: userId, $nin: excludedPhones }
            }).sort({ createdAt: 1 }).lean();

            if (!roomToJoin) break;

            hostSocket = io.sockets.sockets.get(roomToJoin.socketIds.host);
            if (hostSocket && hostSocket.connected) {
                break; // Found a valid partner
            } else {
                // Stale room (host disconnected), it's already deleted by findOneAndDelete
                console.log(`[EphemeralMatch] Cleaning up stale room: ${roomToJoin.roomId}`);
                roomToJoin = null;
                hostSocket = null;
            }
        }

        if (roomToJoin && hostSocket) {
            // MATCH IN RAM ONLY
            const sessionId = crypto.randomBytes(4).toString('hex');
            const roomId = roomToJoin.roomId;

            socket.partnerSocketId = hostSocket.id;
            socket.currentRoomId = roomId;
            hostSocket.partnerSocketId = socket.id;
            hostSocket.currentRoomId = roomId;

            hostSocket.join(roomId);
            socket.join(roomId);

            const payload = { roomId, sessionId, ts: Date.now() };

            // Notify both
            io.to(hostSocket.id).emit('random_match_found', {
                ...payload, partnerId: userId, partnerSocketId: socket.id, role: 'receiver'
            });

            socket.emit('random_match_found', {
                ...payload, partnerId: roomToJoin.hostId, partnerSocketId: hostSocket.id, role: 'caller'
            });
            console.log(`[EphemeralMatch] Match Found: ${userId} <-> ${roomToJoin.hostId}`);
            return;
        }

        // 5. BECOME HOST (Post a temporary notice)
        const roomId = `rnd_${crypto.randomBytes(3).toString('hex')}_${userId.slice(-4)}`;
        const newRoom = new RandomRoom({
            roomId, hostId: userId, socketIds: { host: socket.id }, status: 'waiting'
        });

        await newRoom.save();
        socket.currentRoomId = roomId;
        socket.emit('random_room_created', { roomId });
        console.log(`[EphemeralMatch] Room Created: ${roomId} for ${userId}`);

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
