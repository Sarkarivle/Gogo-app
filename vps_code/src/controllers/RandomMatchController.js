const RandomRoom = require('../models/RandomRoom');
const User = require('../models/User');
const Block = require('../models/Block');
const { normalize } = require('../utils/phoneUtils');

const getRandomItem = (arr) => arr[Math.floor(Math.random() * arr.length)];

exports.findPartner = async (io, socket, data) => {
    const userId = normalize(data.userId || socket.userPhone);
    if (!userId) return;

    try {
        console.log(`[RandomMatch] User ${userId} searching for partner...`);

        // Cleanup any stale rooms for this user
        await RandomRoom.deleteMany({
            $or: [{ hostId: userId }, { guestId: userId }]
        });

        // 1. Fetch Blocked Users (Both ways) using regex to handle variations
        const blocks = await Block.find({
            $or: [
                { blockerPhone: new RegExp(userId + '$') },
                { blockedPhone: new RegExp(userId + '$') }
            ]
        });

        const blockedPhones = blocks.map(b => {
            const b1 = normalize(b.blockerPhone);
            const b2 = normalize(b.blockedPhone);
            return b1 === userId ? b2 : b1;
        });

        // 2. Find waiting rooms excluding blocked users
        const waitingRooms = await RandomRoom.find({
            status: 'waiting',
            hostId: { $ne: userId, $nin: blockedPhones }
        }).limit(10);

        if (waitingRooms.length > 0) {
            const selectedRoom = getRandomItem(waitingRooms);

            const joinedRoom = await RandomRoom.findOneAndUpdate(
                { _id: selectedRoom._id, status: 'waiting' },
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
                console.log(`[RandomMatch] Atomic Match! ${joinedRoom.hostId} <-> ${userId}`);

                const hostSocket = io.sockets.sockets.get(joinedRoom.socketIds.host);
                if (hostSocket) hostSocket.join(joinedRoom.roomId);
                socket.join(joinedRoom.roomId);

                io.to(joinedRoom.socketIds.host).emit('random_match_found', {
                    roomId: joinedRoom.roomId,
                    partnerId: userId,
                    role: 'receiver'
                });

                io.to(socket.id).emit('random_match_found', {
                    roomId: joinedRoom.roomId,
                    partnerId: joinedRoom.hostId,
                    role: 'caller'
                });
                return;
            }
        }

        const roomId = `random_${Date.now()}_${userId.slice(-4)}`;
        const newRoom = new RandomRoom({
            roomId: roomId,
            hostId: userId,
            socketIds: { host: socket.id },
            status: 'waiting'
        });

        await newRoom.save();
        socket.join(roomId);
        console.log(`[RandomMatch] New waiting room: ${roomId} for ${userId}`);
        socket.emit('random_room_created', { roomId });

    } catch (err) {
        console.error("[RandomMatch] findPartner Error:", err);
    }
};

exports.leaveRoom = async (io, socket, userId) => {
    try {
        const normalizedId = normalize(userId || socket.userPhone);
        if (!normalizedId) return;

        const room = await RandomRoom.findOne({
            $or: [{ hostId: normalizedId }, { guestId: normalizedId }]
        });

        if (!room) return;

        console.log(`[RandomMatch] User ${normalizedId} leaving room ${room.roomId}.`);

        const partnerSocket = room.hostId === normalizedId ? room.socketIds.guest : room.socketIds.host;

        if (partnerSocket) {
            io.to(partnerSocket).emit('random_partner_left', {
                message: "Partner left",
                autoSearch: true
            });
        }

        await RandomRoom.deleteOne({ _id: room._id });
        socket.leave(room.roomId);

    } catch (err) {
        console.error("[RandomMatch] leaveRoom Error:", err);
    }
};

exports.handleNextPartner = async (io, socket, data) => {
    const userId = normalize(data.userId || socket.userPhone);
    await exports.leaveRoom(io, socket, userId);
    socket.emit('random_searching_again');
};

exports.handleSignaling = async (io, socket, data, type) => {
    const { roomId, targetId, ...payload } = data;
    if (!roomId) return;

    try {
        if (type === 'offer') {
            await RandomRoom.updateOne({ roomId }, { status: 'connected' });
        }
        socket.to(roomId).emit(`random_${type}`, payload);
    } catch (e) {
        console.error(`[RandomMatch] Signaling Error (${type}):`, e);
    }
};

exports.handleBlock = async (io, socket, data) => {
    const { roomId, targetId } = data;
    if (!roomId) return;

    try {
        console.log(`[RandomMatch] User blocked in room ${roomId}. Target: ${targetId}`);

        socket.to(roomId).emit('random_partner_blocked', {
            message: "You have been blocked by the partner."
        });

        await RandomRoom.deleteOne({ roomId });
    } catch (e) {
        console.error("[RandomMatch] handleBlock Error:", e);
    }
};

exports.performGlobalCleanup = async () => {
    try {
        await RandomRoom.deleteMany({
            $or: [
                { expiresAt: { $lt: new Date() } },
                { status: 'closing' }
            ]
        });
    } catch (e) {
        console.error("[RandomMatch] Global Cleanup error:", e);
    }
};
