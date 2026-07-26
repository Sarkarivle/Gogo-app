const { Queue, Worker } = require('bullmq');
const User = require('../../../users/models/User');
const Message = require('../../models/Message');
const ConversationMemory = require('../models/ConversationMemory');
const aiPersonaService = require('../services/aiPersonaService');
const notificationService = require('../../../../shared/services/notificationService');
const { updateConversationSummary } = require('../../utils/chatUtils');

const QUEUE_NAME = 'ai-proactive-scan';
const MEMORY_WINDOW = 20;
const SUMMARY_EVERY_N_TURNS = 20;

const MIN_FAMILIAR_TURNS = 5; // never message someone she's barely spoken to
const INACTIVITY_HOURS = parseFloat(process.env.PROACTIVE_INACTIVITY_HOURS || '8');
const SCAN_INTERVAL_MS = parseInt(process.env.PROACTIVE_SCAN_INTERVAL_MS || String(30 * 60 * 1000), 10); // 30 min
const BATCH_SIZE = parseInt(process.env.PROACTIVE_BATCH_SIZE || '50', 10);

// Quiet hours in IST — messaging someone unprompted at 3am reads as
// intrusive, not caring, no matter how well-written the message is.
const QUIET_START_HOUR = parseInt(process.env.PROACTIVE_QUIET_START_HOUR_IST || '23', 10);
const QUIET_END_HOUR = parseInt(process.env.PROACTIVE_QUIET_END_HOUR_IST || '8', 10);
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

function getISTHour(date) {
    return new Date(date.getTime() + IST_OFFSET_MS).getUTCHours();
}

function isQuietHourNow() {
    const hour = getISTHour(new Date());
    // handles wrap-around (e.g. 23 -> 8 spans midnight)
    if (QUIET_START_HOUR > QUIET_END_HOUR) {
        return hour >= QUIET_START_HOUR || hour < QUIET_END_HOUR;
    }
    return hour >= QUIET_START_HOUR && hour < QUIET_END_HOUR;
}

function startOfTodayIST() {
    const now = new Date();
    const istNow = new Date(now.getTime() + IST_OFFSET_MS);
    const istMidnightUTC = Date.UTC(istNow.getUTCFullYear(), istNow.getUTCMonth(), istNow.getUTCDate(), 0, 0, 0);
    return new Date(istMidnightUTC - IST_OFFSET_MS);
}

/**
 * Sends one proactive opener to a single (creator, user) conversation.
 * Mirrors aiReplyWorker's send/persist logic so the message behaves exactly
 * like a normal AI reply once it lands (deliverable, counted in memory,
 * summarizable later) — the only difference is nobody sent a message first.
 */
async function sendProactiveMessage(memory, io) {
    const [creator, messagingUser] = await Promise.all([
        User.findOne({ phone: memory.creatorPhone, isCreator: true }).lean(),
        User.findOne({ phone: memory.userPhone }, 'fcmToken').lean()
    ]);
    if (!creator) return;

    const reply = await aiPersonaService.generateProactiveMessage({ creator, memory });
    if (!reply) return; // generation failed — skip silently, try again next scan

    const timestamp = new Date();
    const newMessage = new Message({
        roomId: memory.roomId,
        senderPhone: memory.creatorPhone,
        receiverPhone: memory.userPhone,
        message: reply,
        type: 'text',
        isDelivered: !!(io.onlineUsers && io.onlineUsers.has(memory.userPhone)),
        timestamp
    });
    await newMessage.save();

    const payload = { ...newMessage.toObject(), roomId: memory.roomId };
    io.to(memory.roomId).emit('receive_message', payload);
    io.to(`user_${memory.userPhone}`).emit('receive_message', payload);

    try {
        await updateConversationSummary(newMessage);
    } catch (e) {
        console.error('AI_PROACTIVE updateConversationSummary failed:', e.message);
    }

    // Push notification is essential here — unlike a reactive reply, the user
    // has no reason to have the app open when this fires.
    if (messagingUser?.fcmToken) {
        notificationService.sendPushNotification(
            messagingUser.fcmToken,
            creator.name || 'Someone',
            reply,
            { type: 'chat', senderPhone: memory.creatorPhone, senderName: creator.name || 'Someone', roomId: memory.roomId }
        ).catch(() => {});
    }

    memory.lastMessages.push({ role: 'assistant', text: reply, timestamp });
    memory.turnsSinceSummary = (memory.turnsSinceSummary || 0) + 1;
    memory.totalTurns = (memory.totalTurns || 0) + 1;
    memory.lastProactiveMessageAt = timestamp;
    memory.updatedAt = timestamp;

    if (memory.turnsSinceSummary >= SUMMARY_EVERY_N_TURNS || memory.lastMessages.length > MEMORY_WINDOW) {
        memory.summary = await aiPersonaService.summarizeMemory(memory);
        memory.turnsSinceSummary = 0;
        memory.lastMessages = memory.lastMessages.slice(-6);
    } else if (memory.lastMessages.length > MEMORY_WINDOW) {
        memory.lastMessages = memory.lastMessages.slice(-MEMORY_WINDOW);
    }

    await memory.save();
    console.log(`🤖 AI_PROACTIVE sent opener in room ${memory.roomId}`);
}

async function runScan(io) {
    if (!(await aiPersonaService.isProactiveFeatureEnabled())) return;
    if (isQuietHourNow()) return;

    const inactivityThreshold = new Date(Date.now() - INACTIVITY_HOURS * 60 * 60 * 1000);
    const todayStartUTC = startOfTodayIST();

    const candidates = await ConversationMemory.find({
        totalTurns: { $gte: MIN_FAMILIAR_TURNS },
        updatedAt: { $lt: inactivityThreshold },
        $or: [
            { lastProactiveMessageAt: { $exists: false } },
            { lastProactiveMessageAt: null },
            { lastProactiveMessageAt: { $lt: todayStartUTC } }
        ]
    }).limit(BATCH_SIZE);

    for (const memory of candidates) {
        try {
            await sendProactiveMessage(memory, io);
        } catch (e) {
            console.error(`AI_PROACTIVE failed for room ${memory.roomId}:`, e.message);
        }
    }
}

let worker = null;
async function start(io, redisConnection) {
    if (worker) return worker;

    const queue = new Queue(QUEUE_NAME, { connection: redisConnection });
    await queue.add('scan', {}, {
        repeat: { every: SCAN_INTERVAL_MS },
        removeOnComplete: 5,
        removeOnFail: 5
    });

    worker = new Worker(QUEUE_NAME, () => runScan(io), {
        connection: redisConnection,
        concurrency: 1
    });

    worker.on('failed', (job, err) => {
        console.error('AI_PROACTIVE scan job failed:', err.message);
    });

    console.log('🤖 AI proactive-message worker started');
    return worker;
}

module.exports = { start, QUEUE_NAME };
