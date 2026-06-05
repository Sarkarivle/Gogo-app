const RandomRoom = require('../models/RandomRoom');
const Block = require('../models/Block');
const { normalize } = require('../utils/phoneUtils');
const crypto = require('crypto');

/**
 * PRODUCTION-READY RANDOM MATCH CONTROLLER (High-Stability Version)
 */

exports.findPartner = async (io, socket, data) => {
    const userId = socket.userPhone;
    if (!userId) return;

    const lastPartnerId = data?.lastPartnerId ? normalize(data.lastPartnerId) : null;

    try {
        // 1. DEEP CLEANUP: Pehle purani kisi bhi call se poori tarah bahar niklo
        // Isse "Stuck Screen" wala issue solve hoga
        await exports.leaveRoom(io, socket, false);

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

        // 3. FIND POTENTIAL MATCH
        let waitingRooms = await RandomRoom.find({
            status: 'waiting',
            hostId: { $ne: userId, $nin: excludedPhones }
        }).sort({ createdAt: 1 }).limit(15);

        if (waitingRooms.length > 0) {
            waitingRooms = waitingRooms.sort(() => Math.random() - 0.5);

            for (const room of waitingRooms) {
                const hostSocket = io.sockets.sockets.get(room.socketIds.host);
                if (!hostSocket || !hostSocket.connected) {
                    await RandomRoom.deleteOne({ _id: room._id });
                    continue;
                }

                // ATOMIC JOIN
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
                    console.log(`[RandomMatch] Success: ${joinedRoom.hostId} <-> ${userId}`);

                    hostSocket.join(joinedRoom.roomId);
                    socket.join(joinedRoom.roomId);

                    const matchPayload = {
                        roomId: joinedRoom.roomId,
                        partnerId: userId,
                        partnerSocketId: socket.id,
                        role: 'receiver',
                        timestamp: Date.now()
                    };

                    io.to(joinedRoom.socketIds.host).emit('random_match_found', matchPayload);

                    socket.emit('random_match_found', {
                        ...matchPayload,
                        partnerId: joinedRoom.hostId,
                        partnerSocketId: joinedRoom.socketIds.host,
                        role: 'caller'
                    });
                    return;
                }
            }
        }

        // 4. NO MATCH: Host a new room
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
        socket.emit('random_error', { message: "Internal error" });
    }
};

/**
 * FIXED SIGNALING: Prevents Triple-Emission (Signal Bombing)
 * This stops UI from getting stuck and buttons from freezing.
 */
exports.handleSignaling = (io, socket, data, type) => {
    if (!data || typeof data !== 'object') return;

    const { partnerSocketId, roomId, partnerId } = data;
    const sid = crypto.randomBytes(6).toString('hex');
    const payload = { ...data, sid, fromSocketId: socket.id, ts: Date.now() };

    // PRIORITY LOGIC: Send through ONLY ONE path to avoid client-side state freeze
    if (partnerSocketId && io.sockets.sockets.has(partnerSocketId)) {
        // Path 1: Direct Socket (Best)
        io.to(partnerSocketId).emit(`random_${type}`, payload);
    } else if (roomId) {
        // Path 2: Room (Fallback)
        socket.to(roomId).emit(`random_${type}`, payload);
    } else if (partnerId) {
        // Path 3: Phone Channel (Last Resort)
        io.to(`user_${normalize(partnerId)}`).emit(`random_${type}`, payload);
    }
};

exports.leaveRoom = async (io, socket, notifyPartner = true) => {
    try {
        const userId = socket.userPhone;
        if (!userId) return;

        const room = await RandomRoom.findOneAndDelete({
            $or: [{ hostId: userId }, { guestId: userId }]
        });

        if (!room) return;

        if (notifyPartner) {
            const partnerSocketId = room.hostId === userId ? room.socketIds.guest : room.socketIds.host;
            const partnerId = room.hostId === userId ? room.guestId : room.hostId;

            if (partnerSocketId) {
                io.to(partnerSocketId).emit('random_partner_left', { autoSearch: true });
            } else if (partnerId) {
                io.to(`user_${normalize(partnerId)}`).emit('random_partner_left', { autoSearch: true });
            }
        }

        socket.leave(room.roomId);
    } catch (err) {
        console.error("[RandomMatch] leaveRoom Error:", err);
    }
};

exports.handleNextPartner = async (io, socket, data) => {
    await exports.leaveRoom(io, socket, true);
    socket.emit('random_searching_again');
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
        const expiry = new Date(Date.now() - 3 * 60 * 1000);
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
