const RandomRoom = require('../models/RandomRoom');
const Block = require('../models/Block');
const { normalize } = require('../utils/phoneUtils');
const crypto = require('crypto');

/**
 * ULTRA-STABLE RANDOM MATCH CONTROLLER (Final Fix for UI Freeze)
 */

exports.findPartner = async (io, socket, data) => {
    const userId = socket.userPhone;
    if (!userId) return;

    try {
        // 1. ABSOLUTE CLEANUP: Remove ALL previous traces of this user from DB
        // This ensures no ghost rooms or multiple session conflicts exist.
        await RandomRoom.deleteMany({
            $or: [{ hostId: userId }, { guestId: userId }]
        });

        const lastPartnerId = data?.lastPartnerId ? normalize(data.lastPartnerId) : null;

        // 2. BLOCKLIST & LOOP PROTECTION
        const blocks = await Block.find({
            $or: [{ blockerPhone: userId }, { blockedPhone: userId }]
        }, 'blockerPhone blockedPhone');

        const excludedPhones = blocks.map(b => {
            const b1 = normalize(b.blockerPhone);
            const b2 = normalize(b.blockedPhone);
            return b1 === userId ? b2 : b1;
        });
        if (lastPartnerId) excludedPhones.push(lastPartnerId);

        // 3. ATTEMPT MATCHING
        let waitingRooms = await RandomRoom.find({
            status: 'waiting',
            hostId: { $ne: userId, $nin: excludedPhones }
        }).sort({ createdAt: 1 }).limit(10);

        if (waitingRooms.length > 0) {
            waitingRooms = waitingRooms.sort(() => Math.random() - 0.5);

            for (const room of waitingRooms) {
                const hostSocket = io.sockets.sockets.get(room.socketIds.host);
                if (!hostSocket || !hostSocket.connected) {
                    await RandomRoom.deleteOne({ _id: room._id });
                    continue;
                }

                const sessionId = crypto.randomBytes(4).toString('hex');
                const joinedRoom = await RandomRoom.findOneAndUpdate(
                    { _id: room._id, status: 'waiting' },
                    {
                        $set: {
                            guestId: userId,
                            'socketIds.guest': socket.id,
                            status: 'connecting'
                        }
                    },
                    { new: true }
                );

                if (joinedRoom) {
                    hostSocket.join(joinedRoom.roomId);
                    socket.join(joinedRoom.roomId);

                    const basePayload = {
                        roomId: joinedRoom.roomId,
                        sessionId: sessionId,
                        timestamp: Date.now()
                    };

                    // Receiver (Host)
                    io.to(joinedRoom.socketIds.host).emit('random_match_found', {
                        ...basePayload,
                        partnerId: userId,
                        partnerSocketId: socket.id,
                        role: 'receiver'
                    });

                    // Caller (Guest)
                    socket.emit('random_match_found', {
                        ...basePayload,
                        partnerId: joinedRoom.hostId,
                        partnerSocketId: joinedRoom.socketIds.host,
                        role: 'caller'
                    });
                    return;
                }
            }
        }

        // 4. BECOME HOST
        const roomId = `rnd_${crypto.randomBytes(4).toString('hex')}_${userId.slice(-4)}`;
        const newRoom = new RandomRoom({
            roomId: roomId,
            hostId: userId,
            socketIds: { host: socket.id },
            status: 'waiting'
        });

        await newRoom.save();
        socket.emit('random_room_created', { roomId });

    } catch (err) {
        console.error("[RandomMatch] Error:", err);
        // CRITICAL: Tell the app to unlock buttons in case of error
        socket.emit('random_reset', { message: "Resetting UI due to error" });
    }
};

exports.handleSignaling = (io, socket, data, type) => {
    if (!data || typeof data !== 'object') return;

    const { partnerSocketId, roomId, sessionId } = data;

    // Safety check: Don't signal if we don't know where to go
    if (!partnerSocketId && !roomId) return;

    const payload = {
        ...data,
        fromSocketId: socket.id,
        ts: Date.now()
    };

    // PRIORITY ROUTING: Avoids duplicate signals that freeze the UI
    if (partnerSocketId && io.sockets.sockets.has(partnerSocketId)) {
        io.to(partnerSocketId).emit(`random_${type}`, payload);
    } else if (roomId) {
        socket.to(roomId).emit(`random_${type}`, payload);
    }
};

exports.handleCancelSearch = async (io, socket) => {
    try {
        const userId = socket.userPhone;
        if (!userId) return;

        console.log(`[RandomMatch] Search cancelled by ${userId}`);

        // Perform full cleanup and notify if someone was just connecting
        await exports.leaveRoom(io, socket, true);

        // Tell the client that cancellation is successful
        socket.emit('random_search_cancelled');
    } catch (err) {
        console.error("[RandomMatch] handleCancelSearch Error:", err);
    }
};

exports.leaveRoom = async (io, socket, notifyPartner = true) => {
    try {
        const userId = socket.userPhone;
        if (!userId) return;

        // 1. Quick fetch for notification details
        const rooms = await RandomRoom.find({
            $or: [{ hostId: userId }, { guestId: userId }]
        }).lean();

        // 2. Immediate Bulk Delete (Fastest)
        RandomRoom.deleteMany({
            $or: [{ hostId: userId }, { guestId: userId }]
        }).exec();

        for (const room of rooms) {
            if (notifyPartner) {
                const partnerSocketId = room.hostId === userId ? room.socketIds.guest : room.socketIds.host;
                if (partnerSocketId) {
                    io.to(partnerSocketId).emit('random_partner_left', { autoSearch: true });
                }
            }
        }

        // Clear socket rooms
        const joinedRooms = Array.from(socket.rooms);
        joinedRooms.forEach(rid => {
            if (rid.startsWith('rnd_')) socket.leave(rid);
        });

    } catch (err) {
        console.error("[RandomMatch] leaveRoom Error:", err);
    }
};

exports.handleNextPartner = async (io, socket, data) => {
    // UNBLOCK UI IMMEDIATELY
    socket.emit('random_searching_again');

    // Background cleanup
    await exports.leaveRoom(io, socket, true);
};

exports.handleBlock = async (io, socket, data) => {
    if (!data || typeof data !== 'object') return;
    const { partnerId, partnerSocketId } = data;
    const userId = socket.userPhone;
    if (!userId || !partnerId) return;

    try {
        await Block.findOneAndUpdate(
            { blockerPhone: userId, blockedPhone: normalize(partnerId) },
            { reason: "Blocked", timestamp: new Date() },
            { upsert: true }
        );

        if (partnerSocketId) {
            io.to(partnerSocketId).emit('random_partner_blocked', { message: "Blocked" });
        }
        await exports.leaveRoom(io, socket, true);
    } catch (e) {
        console.error("[RandomMatch] handleBlock Error:", e);
    }
};

exports.performGlobalCleanup = async () => {
    try {
        const expiry = new Date(Date.now() - 3 * 60 * 1000); // 3 mins
        await RandomRoom.deleteMany({
            $or: [
                { createdAt: { $lt: expiry } },
                { status: { $in: ['closing', 'expired'] } }
            ]
        });
    } catch (e) {
        console.error("[RandomMatch] Cleanup Error:", e);
    }
};
