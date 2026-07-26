const { Worker } = require('bullmq');
const User = require('../../../users/models/User');
const Message = require('../../models/Message');
const ConversationMemory = require('../models/ConversationMemory');
const aiPersonaService = require('../services/aiPersonaService');
const { updateConversationSummary } = require('../../utils/chatUtils');

const QUEUE_NAME = 'ai-creator-replies';
const MEMORY_WINDOW = 20; // raw turns kept before folding into the summary
const SUMMARY_EVERY_N_TURNS = 20;
const MOOD_HISTORY_WINDOW = 5; // short trend, enough to notice a shift without re-analyzing everything
const REMEMBERED_FACTS_WINDOW = 15;

function isSameCalendarDay(a, b) {
    if (!a || !b) return false;
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

const MIN_TYPING_DELAY_MS = 1200;
const MAX_TYPING_DELAY_MS = 4500;
function typingDelayFor(text) {
    const ms = (text || '').length * 35; // ~ human typing speed
    return Math.min(MAX_TYPING_DELAY_MS, Math.max(MIN_TYPING_DELAY_MS, ms));
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Runs the AI reply pipeline for one queued job. Designed to run in-process
 * (given `io` here) on the current single-VPS setup; if this worker is ever
 * split into its own process with no local `io`/socket.io server, swap the
 * `io.to(...).emit(...)` calls below for a `@socket.io/redis-emitter`
 * instance instead — the rest of the pipeline is unchanged.
 */
async function processJob(job, io) {
    const { roomId, creatorPhone, userPhone, messageId } = job.data;

    // Re-check the kill switch inside the worker too, in case it was flipped
    // off after this job was already queued.
    if (!(await aiPersonaService.isFeatureEnabled())) return;

    const [creator, triggerMessage, messagingUser] = await Promise.all([
        User.findOne({ phone: creatorPhone, isCreator: true }).lean(),
        Message.findById(messageId).lean(),
        User.findOne({ phone: userPhone }, 'isPremium').lean()
    ]);
    if (!creator || !triggerMessage) return;
    if (!triggerMessage.message || triggerMessage.type !== 'text') return; // only reply to text for now

    let memory = await ConversationMemory.findOne({ roomId });
    if (!memory) {
        memory = new ConversationMemory({ roomId, creatorPhone, userPhone, lastMessages: [] });
    }

    const isPremiumUser = !!messagingUser?.isPremium;
    const upsellAlreadyMentionedToday = isSameCalendarDay(memory.lastUpsellMentionAt, new Date());

    io.to(`user_${userPhone}`).emit('display_typing', { phone: creatorPhone });

    const { reply, detectedIntent, mood, newFacts, upsellOpportunity, riskFlag } = await aiPersonaService.generateReply({
        creator,
        memory,
        userMessage: triggerMessage.message,
        isPremiumUser,
        upsellAlreadyMentionedToday
    });

    const finalReply = aiPersonaService.RISK_LEVELS_REQUIRING_SAFE_REPLY.has(riskFlag)
        ? aiPersonaService.SAFE_REDIRECT_REPLY
        : reply;

    if (aiPersonaService.RISK_LEVELS_REQUIRING_SAFE_REPLY.has(riskFlag)) {
        memory.flaggedForReview = true;
        console.warn(`AI_PERSONA risk flag "${riskFlag}" raised in room ${roomId} — flagged for review.`);
    }

    await sleep(typingDelayFor(finalReply));
    io.to(`user_${userPhone}`).emit('hide_typing', { phone: creatorPhone });

    const shouldTagUpsell = upsellOpportunity !== 'none' && !isPremiumUser && !upsellAlreadyMentionedToday;

    const timestamp = new Date();
    const newMessage = new Message({
        roomId,
        senderPhone: creatorPhone,
        receiverPhone: userPhone,
        message: finalReply,
        type: 'text',
        isDelivered: !!(io.onlineUsers && io.onlineUsers.has(userPhone)),
        timestamp,
        // Tells the client to auto-open the paywall shortly after this bubble
        // renders — only set when the nudge was actually eligible to fire
        // this turn (same guards as the daily-cap bookkeeping below).
        metadata: shouldTagUpsell ? { aiUpsell: upsellOpportunity } : undefined
    });
    await newMessage.save();

    const payload = { ...newMessage.toObject(), roomId };
    io.to(roomId).emit('receive_message', payload);
    io.to(`user_${userPhone}`).emit('receive_message', payload);

    try {
        await updateConversationSummary(newMessage);
    } catch (e) {
        console.error('AI_PERSONA updateConversationSummary failed:', e.message);
    }

    // --- update bounded memory ---
    memory.lastMessages.push({ role: 'user', text: triggerMessage.message, timestamp: triggerMessage.timestamp });
    memory.lastMessages.push({ role: 'assistant', text: finalReply, timestamp });
    memory.lastDetectedIntent = detectedIntent;
    memory.lastDetectedMood = mood;
    memory.moodHistory.push({ mood, timestamp });
    if (memory.moodHistory.length > MOOD_HISTORY_WINDOW) {
        memory.moodHistory = memory.moodHistory.slice(-MOOD_HISTORY_WINDOW);
    }

    // Remembered facts: skip near-duplicates of what's already stored so the
    // list doesn't fill up with the same fact reworded slightly each time.
    const existingFactsLower = memory.rememberedFacts.map(f => f.fact.toLowerCase());
    for (const fact of (newFacts || [])) {
        const factLower = fact.toLowerCase();
        const isDuplicate = existingFactsLower.some(existing => existing.includes(factLower) || factLower.includes(existing));
        if (!isDuplicate) {
            memory.rememberedFacts.push({ fact, learnedAt: timestamp });
            existingFactsLower.push(factLower);
        }
    }
    if (memory.rememberedFacts.length > REMEMBERED_FACTS_WINDOW) {
        memory.rememberedFacts = memory.rememberedFacts.slice(-REMEMBERED_FACTS_WINDOW);
    }

    // Monetization nudge: only counts toward the daily cap if it was actually
    // eligible to fire this turn (never for premium users, never re-armed
    // just because the model happened to set the flag on a already-capped day).
    if (shouldTagUpsell) {
        memory.lastUpsellMentionAt = timestamp;
    }

    memory.turnsSinceSummary = (memory.turnsSinceSummary || 0) + 1;
    memory.totalTurns = (memory.totalTurns || 0) + 1;
    memory.updatedAt = new Date();

    if (memory.turnsSinceSummary >= SUMMARY_EVERY_N_TURNS || memory.lastMessages.length > MEMORY_WINDOW) {
        memory.summary = await aiPersonaService.summarizeMemory(memory);
        memory.turnsSinceSummary = 0;
        memory.lastMessages = memory.lastMessages.slice(-6); // keep a small tail for immediate continuity
    } else if (memory.lastMessages.length > MEMORY_WINDOW) {
        memory.lastMessages = memory.lastMessages.slice(-MEMORY_WINDOW);
    }

    await memory.save();
}

let worker = null;
function start(io, redisConnection) {
    if (worker) return worker;

    worker = new Worker(QUEUE_NAME, (job) => processJob(job, io), {
        connection: redisConnection,
        concurrency: parseInt(process.env.AI_WORKER_CONCURRENCY || '20', 10)
    });

    worker.on('failed', (job, err) => {
        console.error(`AI_PERSONA job ${job?.id} failed:`, err.message);
    });

    console.log('🤖 AI creator-reply worker started');
    return worker;
}

module.exports = { start, QUEUE_NAME };
