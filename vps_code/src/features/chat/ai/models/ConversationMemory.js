const mongoose = require('mongoose');

// Bounded per-room memory for AI creator replies: a rolling window of raw turns
// plus a periodically-regenerated summary, so prompt size (and cost/latency)
// stays flat no matter how long a user has been chatting with a creator.
const ConversationMemorySchema = new mongoose.Schema({
    roomId: { type: String, required: true, unique: true, index: true },
    creatorPhone: { type: String, required: true, index: true },
    userPhone: { type: String, required: true, index: true },
    summary: { type: String, default: '' },
    lastMessages: [{
        role: { type: String, enum: ['user', 'assistant'] },
        text: String,
        timestamp: { type: Date, default: Date.now }
    }],
    turnsSinceSummary: { type: Number, default: 0 },
    // Total AI-reply turns across the whole relationship (never reset, unlike
    // turnsSinceSummary) — used to auto-derive relationship stage server-side
    // instead of an admin having to set it manually per creator.
    totalTurns: { type: Number, default: 0 },
    lastDetectedIntent: String,
    lastDetectedMood: String,
    // Short rolling trend (bounded, oldest first) so the model can notice
    // mood shifts across turns (e.g. happy -> quiet -> sad) without us
    // re-reading/re-analyzing the whole conversation every time.
    moodHistory: [{
        mood: String,
        timestamp: { type: Date, default: Date.now }
    }],
    flaggedForReview: { type: Boolean, default: false },
    // Discrete facts learned about the user (not a vague summary) so the model
    // can reference specifics unprompted later — e.g. "wait, don't you have 3
    // siblings?" — instead of only ever reacting to what's said in-the-moment.
    rememberedFacts: [{
        fact: String,
        learnedAt: { type: Date, default: Date.now }
    }],
    // Daily-cap guards for the two unprompted-message behaviors (proactive
    // check-ins and monetization nudges) — both would feel spammy/salesy if
    // they fired every scan/every message instead of at most once a day.
    lastProactiveMessageAt: Date,
    lastUpsellMentionAt: Date,
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now }
});

// Supports the proactive-message worker's scan: "familiar/close conversations
// that have gone quiet for a while."
ConversationMemorySchema.index({ totalTurns: 1, updatedAt: 1 });

module.exports = mongoose.model('ConversationMemory', ConversationMemorySchema);
