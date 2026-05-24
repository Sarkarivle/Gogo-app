const RandomRoom = require('../models/RandomRoom');
const User = require('../models/User');
const Block = require('../models/Block');

const getRandomItem = (arr) => arr[Math.floor(Math.random() * arr.length)];

exports.findPartner = async (io, socket, data) => {
    const { userId } = data;
    if (!userId) return;

    try {
        console.log(`[RandomMatch] User ${userId} searching for partner...`);

        await RandomRoom.deleteMany({
            $or: [{ hostId: userId }, { guestId: userId }]
        });

        // 1. Fetch Blocked Users (Both ways)
        const blocks = await Block.find({
            $or: [{ blockerPhone: userId }, { blockedPhone: userId }]
        });
        const blockedPhones = blocks.map(b => b.blockerPhone === userId ? b.blockedPhone : b.blockerPhone);

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

                // IMPORTANT: Make both users JOIN the socket room for signaling
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
        socket.join(roomId); // Host joins their own room immediately
        console.log(`[RandomMatch] New waiting room: ${roomId} for ${userId}`);
        socket.emit('random_room_created', { roomId });

    } catch (err) {
        console.error("[RandomMatch] findPartner Error:", err);
    }
};

exports.leaveRoom = async (io, socket, userId) => {
    try {
        if (!userId) return;

        const room = await RandomRoom.findOne({
            $or: [{ hostId: userId }, { guestId: userId }]
        });

        if (!room) return;

        console.log(`[RandomMatch] User ${userId} leaving room ${room.roomId}.`);

        const partnerSocket = room.hostId === userId ? room.socketIds.guest : room.socketIds.host;

        if (partnerSocket) {
            io.to(partnerSocket).emit('random_partner_left', {
                message: "Partner left",
                autoSearch: true
            });
        }

        await RandomRoom.deleteOne({ _id: room._id });
        // Optionally leave socket room
        socket.leave(room.roomId);

    } catch (err) {
        console.error("[RandomMatch] leaveRoom Error:", err);
    }
};

exports.handleNextPartner = async (io, socket, data) => {
    const { userId } = data;
    await exports.leaveRoom(io, socket, userId);
    socket.emit('random_searching_again');
};

exports.handleSignaling = async (io, socket, data, type) => {
    const { roomId, targetId, ...payload } = data;

    if (type === 'offer') {
        await RandomRoom.updateOne({ roomId }, { status: 'connected' });
    }

    // Emit to room (partner will receive)
    socket.to(roomId).emit(`random_${type}`, payload);
};

exports.handleBlock = async (io, socket, data) => {
    const { roomId, targetId } = data;
    console.log(`[RandomMatch] User blocked in room ${roomId}. Target: ${targetId}`);

    // Notify target
    socket.to(roomId).emit('random_partner_blocked', {
        message: "You have been blocked by the partner."
    });

    // Cleanup room
    await RandomRoom.deleteOne({ roomId });
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
