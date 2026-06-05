const RandomRoom = require('../models/RandomRoom');
const Block = require('../models/Block');
const { normalize } = require('../utils/phoneUtils');
const crypto = require('crypto');

/**
 * ADVANCED RANDOM MATCH CONTROLLER (High-Concurrency Optimized)
 */

exports.findPartner = async (io, socket, data) => {
    const userId = socket.userPhone;
    if (!userId) return;

    const lastPartnerId = data?.lastPartnerId ? normalize(data.lastPartnerId) : null;

    try {
        // 1. SILENT CLEANUP: Quick check for any dead rooms this user owns
        // Using deleteMany sparingly to avoid DB lock
        await RandomRoom.deleteMany({ hostId: userId, status: 'waiting' });

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

        // 3. FIND POTENTIAL MATCH (Prioritize Active Hosts)
        // We limit to 20 to shuffle them and reduce 'thundering herd' effect on a single record
        let waitingRooms = await RandomRoom.find({
            status: 'waiting',
            hostId: { $ne: userId, $nin: excludedPhones }
        }).sort({ createdAt: 1 }).limit(10);

        if (waitingRooms.length > 0) {
            // Shuffle to prevent multiple users hitting the exact same record
            waitingRooms = waitingRooms.sort(() => Math.random() - 0.5);

            for (const room of waitingRooms) {
                // ADVANCED: Pre-verification of host socket status
                const hostSocket = io.sockets.sockets.get(room.socketIds.host);
                if (!hostSocket || !hostSocket.connected) {
                    await RandomRoom.deleteOne({ _id: room._id });
                    continue;
                }

                // ATOMIC MATCHING: Ensures only ONE person can join this room
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
                    console.log(`[AdvancedMatch] Atomic Success: ${joinedRoom.hostId} <-> ${userId}`);

                    // Server-side Force Join
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

        // 4. NO MATCH FOUND: Become the Host
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
        console.error("[AdvancedMatch] Critical Error:", err);
        socket.emit('random_error', { message: "Internal matching error" });
    }
};

exports.handleSignaling = (io, socket, data, type) => {
    // CRITICAL FIX: Safety check to prevent crash on null/undefined data
    if (!data || typeof data !== 'object') return;

    const { partnerSocketId, roomId, partnerId } = data;

    // ADVANCED: Add Signal ID (sid) to prevent triple-processing on client
    const sid = crypto.randomBytes(6).toString('hex');
    const enhancedPayload = {
        ...data,
        sid: sid,
        fromSocketId: socket.id,
        serverTimestamp: Date.now()
    };

    // 1. Direct Socket (Primary & Fastest)
    if (partnerSocketId && typeof partnerSocketId === 'string') {
        io.to(partnerSocketId).emit(`random_${type}`, enhancedPayload);
    }

    // 2. Room (Secondary/Legacy Support)
    if (roomId && typeof roomId === 'string') {
        socket.to(roomId).emit(`random_${type}`, enhancedPayload);
    }

    // 3. Phone Channel (Fallback/Reliability)
    if (partnerId) {
        io.to(`user_${normalize(partnerId)}`).emit(`random_${type}`, enhancedPayload);
    }
};

exports.leaveRoom = async (io, socket) => {
    try {
        const userId = socket.userPhone;
        if (!userId) return;

        // Atomic find and remove
        const room = await RandomRoom.findOneAndDelete({
            $or: [{ hostId: userId }, { guestId: userId }]
        });

        if (!room) return;

        const partnerSocketId = room.hostId === userId ? room.socketIds.guest : room.socketIds.host;
        const partnerId = room.hostId === userId ? room.guestId : room.hostId;

        if (partnerSocketId) {
            io.to(partnerSocketId).emit('random_partner_left', { autoSearch: true });
        } else if (partnerId) {
            // Fallback to phone channel if socket is lost
            io.to(`user_${normalize(partnerId)}`).emit('random_partner_left', { autoSearch: true });
        }

    } catch (err) {
        console.error("[AdvancedMatch] leaveRoom Error:", err);
    }
};

exports.handleNextPartner = async (io, socket, data) => {
    await exports.leaveRoom(io, socket);
    socket.emit('random_searching_again');
};

exports.handleBlock = async (io, socket, data) => {
    // CRITICAL FIX: Safety check
    if (!data || typeof data !== 'object') return;
    const { partnerId, partnerSocketId } = data;

    const userId = socket.userPhone;
    if (!userId || !partnerId) return;

    try {
        await Block.findOneAndUpdate(
            { blockerPhone: userId, blockedPhone: normalize(partnerId) },
            { reason: "Random Call Block", timestamp: new Date() },
            { upsert: true }
        );

        if (partnerSocketId && typeof partnerSocketId === 'string') {
            io.to(partnerSocketId).emit('random_partner_blocked', { message: "Blocked" });
        }
        await exports.leaveRoom(io, socket);
    } catch (e) {
        console.error("[AdvancedMatch] handleBlock Error:", e);
    }
};

exports.performGlobalCleanup = async () => {
    try {
        // Clean rooms older than 3 minutes to keep DB lean
        const expiry = new Date(Date.now() - 3 * 60 * 1000);
        await RandomRoom.deleteMany({
            $or: [
                { createdAt: { $lt: expiry } },
                { status: { $in: ['closing', 'expired'] } }
            ]
        });
    } catch (e) {
        console.error("[AdvancedMatch] Cleanup Error:", e);
    }
};
