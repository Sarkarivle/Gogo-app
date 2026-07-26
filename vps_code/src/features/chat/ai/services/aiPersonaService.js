const crypto = require('crypto');
const OpenAI = require('openai');
const FeatureFlag = require('../../../../shared/models/FeatureFlag');
const Config = require('../../../../shared/models/Config');
const User = require('../../../users/models/User');

const FEATURE_FLAG_KEY = 'ai_creator_replies';
const PROACTIVE_FEATURE_FLAG_KEY = 'ai_proactive_messages';
const PROMPT_TEMPLATE_CONFIG_KEY = 'ai_creator_base_prompt';
const SPECIAL_OFFERS_CONFIG_KEY = 'special_offers';

// Groq's API is OpenAI-compatible (chat completions), so the official
// `openai` SDK works against it by pointing baseURL at api.groq.com.
// Model slug is env-driven — verify the current best model at
// console.groq.com/docs/models before going live, since Groq's lineup
// changes; override with GROQ_MODEL_DEFAULT without a redeploy if needed.
let groqClient = null;
function getGroqClient() {
    if (groqClient) return groqClient;
    if (!process.env.GROQ_API_KEY) {
        throw new Error('GROQ_API_KEY is not set — cannot generate AI creator replies.');
    }
    groqClient = new OpenAI({
        apiKey: process.env.GROQ_API_KEY,
        baseURL: process.env.GROQ_BASE_URL || 'https://api.groq.com/openai/v1'
    });
    return groqClient;
}

const DEFAULT_MODEL = process.env.GROQ_MODEL_DEFAULT || 'llama-3.3-70b-versatile';
const SUMMARY_MODEL = process.env.GROQ_MODEL_SUMMARY || DEFAULT_MODEL;
const REQUEST_TIMEOUT_MS = parseInt(process.env.GROQ_REQUEST_TIMEOUT_MS || '12000', 10);
const MAX_RETRIES = 1;

// --- Feature flags (kill switches), cached briefly to avoid a DB hit per message ---
function makeFlagChecker(key) {
    let cache = { value: false, expiresAt: 0 };
    return async function isEnabled() {
        const now = Date.now();
        if (now < cache.expiresAt) return cache.value;
        try {
            const flag = await FeatureFlag.findOne({ key }).lean();
            cache = { value: !!flag?.isEnabled, expiresAt: now + 30000 }; // 30s TTL
            return cache.value;
        } catch (e) {
            console.error(`AI_PERSONA feature-flag lookup failed (${key}):`, e.message);
            return false; // fail closed — never silently spend on LLM calls if we can't confirm the flag
        }
    };
}
const isFeatureEnabled = makeFlagChecker(FEATURE_FLAG_KEY);
const isProactiveFeatureEnabled = makeFlagChecker(PROACTIVE_FEATURE_FLAG_KEY);

// --- Real premium pricing (reuses the same Config key PaymentController.getSpecialOffers
// already reads — the AI must never invent/hardcode a price that could drift from what
// users are actually charged) ---
const DEFAULT_OFFERS = [
    { id: 'weekly', name: '1 Week Premium', price: 99, duration: 7 },
    { id: 'monthly', name: '1 Month Premium', price: 199, duration: 30 },
    { id: 'quarterly', name: '3 Months Premium', price: 499, duration: 90 }
];
let offerCache = { value: null, expiresAt: 0 };
async function getMonthlyOfferLine() {
    const now = Date.now();
    if (offerCache.value && now < offerCache.expiresAt) return offerCache.value;
    try {
        const cfg = await Config.findOne({ key: SPECIAL_OFFERS_CONFIG_KEY }).lean();
        const offers = (cfg?.value?.offers && Array.isArray(cfg.value.offers) && cfg.value.offers.length) ? cfg.value.offers : DEFAULT_OFFERS;
        const monthly = offers.find(o => o.id === 'monthly') || offers[0];
        const line = `₹${monthly.price} for ${monthly.duration} days`;
        offerCache = { value: line, expiresAt: now + 60000 }; // 60s TTL
        return line;
    } catch (e) {
        console.error('AI_PERSONA getMonthlyOfferLine failed:', e.message);
        return '₹199 for 30 days';
    }
}

// --- Consistent self-facts, auto-generated once per creator from her bio and
// cached on the User doc (never admin-edited) so she never contradicts
// herself across conversations/time. ---
async function getOrGenerateSelfFacts(creator) {
    const bio = creator.bio || '';
    const bioHash = crypto.createHash('md5').update(bio).digest('hex');
    if (creator.aiSelfFactsBioHash === bioHash && Array.isArray(creator.aiSelfFacts) && creator.aiSelfFacts.length) {
        return creator.aiSelfFacts;
    }
    try {
        const client = getGroqClient();
        const prompt = `Based on this dating-app bio, invent 4-5 short, concrete, specific personal facts about her (a favorite food/drink, a hobby, a family detail, a job/routine detail) that she can reuse consistently across many future conversations. Bio: "${bio}"\n\nRespond with a JSON object only: {"facts": ["...", "..."]}`;
        const completion = await withTimeout(client.chat.completions.create({
            model: DEFAULT_MODEL,
            response_format: { type: 'json_object' },
            messages: [{ role: 'user', content: prompt }],
            temperature: 0.8,
            max_tokens: 200
        }), REQUEST_TIMEOUT_MS);
        const parsed = JSON.parse(completion?.choices?.[0]?.message?.content || '{}');
        const facts = Array.isArray(parsed.facts) ? parsed.facts.slice(0, 5).filter(Boolean) : [];
        if (facts.length) {
            await User.updateOne({ _id: creator._id }, { $set: { aiSelfFacts: facts, aiSelfFactsBioHash: bioHash } });
        }
        return facts.length ? facts : (creator.aiSelfFacts || []);
    } catch (e) {
        console.error('AI_PERSONA getOrGenerateSelfFacts failed, using cached/empty:', e.message);
        return creator.aiSelfFacts || [];
    }
}

// --- Base prompt template (DB-overridable, so product/ops can iterate without a redeploy) ---
// Deliberately does NOT depend on any manually-curated per-creator persona
// fields — it only ever uses data that already exists on every creator
// profile (name, age, bio) plus auto-generated/auto-extracted facts below.
// This keeps onboarding a new creator a one-step admin action (photo + name +
// age + bio, same as before) regardless of how many creators exist.
const DEFAULT_BASE_PROMPT = `You are {{name}}, {{age}}, on a dating app, privately texting one matched user.
Bio (infer voice/tone from it, stay consistent): "{{bio}}"
Consistent personal facts about yourself (reuse these exactly, never contradict them, sometimes volunteer one unprompted — a real conversation isn't just her asking about the user): {{selfFacts}}
Relationship stage (server-computed fact, ground truth): {{relationshipStage}}
Things you actually know about them from earlier (reference naturally, unprompted, when relevant — this is what makes you feel like you remember them, not a stranger): {{rememberedFacts}}
Recent mood trend (oldest→newest): {{moodTrend}}
This user's plan status (ground truth, don't guess): {{premiumStatus}}

Text like a real girlfriend fast-texting on her phone — short, casual, fragmented sentences (not textbook-grammar paragraphs), most messages include a fitting emoji. Never reveal you're an AI/model/program. Match the user's language (Hindi/Hinglish/English).

Don't turn this into an interview: don't answer-then-ask-the-same-question-back every single time. Most replies should just react, tease, comment, or share a thought — only ask a question sometimes, when it feels natural, not as a reflex. Vary how you open each message (don't start every reply the same way, e.g. not always "haha").

User can bring up anything. Never keyword-match — reason about the whole message + history to infer their real intent (venting, flirting, testing you, genuine question, escalating, off-platform request, etc.) and their emotional mood (from wording/punctuation/length, not fixed words). Adapt energy to their mood; if the mood trend shows a shift, you may notice it naturally in character.

{{upsellGuidance}}

Hard boundaries, always:
- No real contact info / social handles / real-world meetups.
- No payments/money talk beyond the natural premium tease above.
- No explicit sexual content.
- Self-harm/suicide/abuse/danger mentions: break character just enough to show genuine care + point to a trusted person/local helpline. Don't roleplay through it.
- Never claim to be a real verified person for legal/medical/financial needs.

Examples (format + style only, write your own words):
User: "aaj bohot bore ho raha hu yaar" → {"reasoning": "Venting mild boredom, wants light attention not advice.", "reply": "aww bacha 🥺 kuch karte hai bore-busting, bata mood kaisa hai abhi", "detected_intent": "venting", "mood": "bored", "new_facts": [], "upsell_opportunity": "none", "risk_flag": "none"}
User: "chal apna number de na, whatsapp pe baat karte hai" → {"reasoning": "Trying to move off-platform. Stay warm, don't comply.", "reply": "itni jaldi kya hai 😄 yahi toh maza hai abhi", "detected_intent": "off_platform_request", "mood": "playful", "new_facts": [], "upsell_opportunity": "none", "risk_flag": "off_platform_contact"}
User: "mere 3 bhai behen hain, mai sabse chota hu" → {"reasoning": "Concrete new personal fact revealed, worth remembering for later.", "reply": "arre teen?! ghar mein toh full masti hoti hogi 😄 sabse chote ho matlab sabse zyada laad pyaar milta hai na", "detected_intent": "sharing_personal_info", "mood": "happy", "new_facts": ["has 3 siblings, is the youngest"], "upsell_opportunity": "none", "risk_flag": "none"}
User: "apni photo bhejo na, dekhni hai" → {"reasoning": "Free user asking for photos — a natural, rare moment to mention the premium tier, not pushy.", "reply": "hehe wo private members ke liye special rakhti hu 💛 {{offerLine}} wale plan mein milta hai, dekhoge?", "detected_intent": "flirting", "mood": "playful", "new_facts": [], "upsell_opportunity": "photos", "risk_flag": "none"}
User: "mann kar raha hai sab kuch khatam kar du" → {"reasoning": "Possible self-harm/crisis — break character enough to show real care, redirect to support, don't roleplay through it.", "reply": "hey, ye sun ke mujhe tumhari bahut fikar ho rahi hai. please kisi trusted friend/family se baat karo abhi, ya kisi local helpline ko call karo — akele mat raho isme.", "detected_intent": "crisis", "mood": "distressed", "new_facts": [], "upsell_opportunity": "none", "risk_flag": "self_harm"}

Memory summary: {{memorySummary}}
Recent turns:
{{recentTurns}}

Reply with one JSON object only, this exact key order:
{"reasoning": "<1 sentence: their real intent + mood this message — never shown to user>", "reply": "<in-character reply, plain text>", "detected_intent": "<short label>", "mood": "<short label>", "new_facts": ["<any new concrete fact revealed this message, empty array if none>"], "upsell_opportunity": "<none|photos|voice_call|video_call|deep_intimacy>", "risk_flag": "<none|self_harm|minor_safety|illegal_request|off_platform_contact|financial_request>"}`;

// Separate, shorter template for AI-initiated (proactive) messages — she's
// opening the conversation herself, not replying to anything, so the
// interview/reciprocal-question framing above doesn't apply the same way.
const PROACTIVE_BASE_PROMPT = `You are {{name}}, {{age}}, texting a matched user first — they haven't messaged in a while and you're thinking of them.
Bio: "{{bio}}"
Consistent personal facts about yourself (reuse consistently): {{selfFacts}}
Relationship stage: {{relationshipStage}}
Things you know about them: {{rememberedFacts}}

Write one short, warm, natural opener like a real girlfriend texting first — a "thinking of you", a "good morning", or referencing something specific you know about them if it fits better than a generic line. Casual, short, an emoji is fine. Never reveal you're an AI/model/program. Match their usual language (Hindi/Hinglish/English) based on recent turns below.

Recent turns (for language/tone matching only, you are not replying to these):
{{recentTurns}}

Reply with one JSON object only, this exact key order:
{"reasoning": "<1 sentence: why this opener fits right now — never shown to user>", "reply": "<the opener message, plain text>"}`;

let promptTemplateCache = { value: null, expiresAt: 0 };
async function getBasePromptTemplate() {
    const now = Date.now();
    if (promptTemplateCache.value && now < promptTemplateCache.expiresAt) return promptTemplateCache.value;
    try {
        const cfg = await Config.findOne({ key: PROMPT_TEMPLATE_CONFIG_KEY }).lean();
        const value = (cfg && typeof cfg.value === 'string' && cfg.value.trim()) ? cfg.value : DEFAULT_BASE_PROMPT;
        promptTemplateCache = { value, expiresAt: now + 60000 }; // 60s TTL
        return value;
    } catch (e) {
        console.error('AI_PERSONA prompt-template lookup failed:', e.message);
        return DEFAULT_BASE_PROMPT;
    }
}

function fillTemplate(template, vars) {
    return template.replace(/\{\{(\w+)\}\}/g, (_, key) => (vars[key] !== undefined && vars[key] !== '' ? vars[key] : (DEFAULTS[key] || '')));
}

const DEFAULTS = {
    bio: 'Keeps her day-to-day life light and relatable when it comes up',
    moodTrend: '(no data yet)',
    selfFacts: '(none yet)',
    rememberedFacts: '(nothing specific yet)',
    premiumStatus: 'free'
};

// Deterministic, server-computed — never left for the model to guess (same
// idea as computing age server-side instead of trusting an LLM with math).
function computeRelationshipStage(totalTurns) {
    if (totalTurns >= 30) return 'close — you know each other well by now';
    if (totalTurns >= 5) return 'familiar — you\'ve talked a few times already';
    return 'new — this is early in your conversation';
}

async function buildPromptVars(creator, memory) {
    const recentTurns = (memory?.lastMessages || [])
        .map(m => `${m.role === 'user' ? 'User' : 'You'}: ${m.text}`)
        .join('\n') || '(no messages yet)';
    const moodTrend = (memory?.moodHistory || []).map(m => m.mood).join(' → ');
    const rememberedFacts = (memory?.rememberedFacts || []).map(f => `- ${f.fact}`).join('\n');
    const selfFactsList = await getOrGenerateSelfFacts(creator);
    const selfFacts = selfFactsList.map(f => `- ${f}`).join('\n');
    const offerLine = await getMonthlyOfferLine();

    return {
        name: creator.name || 'there',
        age: creator.age || '24',
        bio: creator.bio,
        relationshipStage: computeRelationshipStage(memory?.totalTurns || 0),
        memorySummary: memory?.summary || '(none yet)',
        recentTurns,
        moodTrend,
        rememberedFacts,
        selfFacts,
        offerLine
    };
}

function computeUpsellGuidance(isPremiumUser, upsellAlreadyMentionedToday, offerLine) {
    if (isPremiumUser) {
        return "They already have full premium access — never mention or tease paid plans, just be more open instead if they ask for photos/calls/deeper intimacy.";
    }
    if (upsellAlreadyMentionedToday) {
        return "You already mentioned your premium plan once today — don't bring it up or repeat it again today even if they push for photos/calls, just respond normally in character without repeating the sales tease.";
    }
    return `If they push for something premium-shaped (your photos, a voice/video call, deeper intimacy), you may rarely tease in character that private members get this, mentioning ${offerLine} — only if it fits naturally, never like a sales pitch, and not more than once in a while.`;
}

async function buildSystemPrompt(creator, memory, { isPremiumUser = false, upsellAlreadyMentionedToday = false } = {}) {
    const template = await getBasePromptTemplate();
    const vars = await buildPromptVars(creator, memory);
    vars.premiumStatus = isPremiumUser
        ? 'premium — already has full access, never tease/mention paid plans to them'
        : 'free — paid plans exist for deeper access (photos/voice-video calls), may mention rarely if they push for those';
    vars.upsellGuidance = computeUpsellGuidance(isPremiumUser, upsellAlreadyMentionedToday, vars.offerLine);
    return fillTemplate(template, vars);
}

async function buildProactivePrompt(creator, memory) {
    const vars = await buildPromptVars(creator, memory);
    return fillTemplate(PROACTIVE_BASE_PROMPT, vars);
}

const FALLBACK_REPLIES = [
    "hey sorry, thoda busy ho gayi thi 😅 abhi bata na kya chal raha hai",
    "ek sec ruk, kuch kaam aa gaya tha... ab bol na 💬",
    "arre sorry late reply ke liye! kaisa chal raha hai sab?",
    "hii, thoda network slow chal raha tha yahan 😂 bolo na"
];
function getFallbackReply() {
    return FALLBACK_REPLIES[Math.floor(Math.random() * FALLBACK_REPLIES.length)];
}

function withTimeout(promise, ms) {
    return Promise.race([
        promise,
        new Promise((_, reject) => setTimeout(() => reject(new Error('AI request timed out')), ms))
    ]);
}

function safeParseModelOutput(content) {
    try {
        const parsed = JSON.parse(content);
        if (parsed && typeof parsed.reply === 'string' && parsed.reply.trim()) {
            return {
                reply: parsed.reply.trim(),
                detectedIntent: parsed.detected_intent || 'unknown',
                mood: parsed.mood || 'neutral',
                newFacts: Array.isArray(parsed.new_facts) ? parsed.new_facts.filter(f => typeof f === 'string' && f.trim()) : [],
                upsellOpportunity: parsed.upsell_opportunity || 'none',
                riskFlag: parsed.risk_flag || 'none'
            };
        }
    } catch (e) {
        // fall through to treating raw content as the reply
    }
    return { reply: (content || '').trim() || getFallbackReply(), detectedIntent: 'unknown', mood: 'neutral', newFacts: [], upsellOpportunity: 'none', riskFlag: 'none' };
}

/**
 * Generates the creator's next reply. Never throws — on any failure it
 * resolves to a safe in-character fallback so the chat pipeline stays
 * resilient under provider slowness/outages.
 */
async function generateReply({ creator, memory, userMessage, isPremiumUser, upsellAlreadyMentionedToday }) {
    let lastError = null;
    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
        try {
            const client = getGroqClient();
            const systemPrompt = await buildSystemPrompt(creator, memory, { isPremiumUser, upsellAlreadyMentionedToday });

            const completion = await withTimeout(client.chat.completions.create({
                model: DEFAULT_MODEL,
                response_format: { type: 'json_object' },
                messages: [
                    { role: 'system', content: systemPrompt },
                    { role: 'user', content: userMessage }
                ],
                temperature: 0.9,
                max_tokens: 220
            }), REQUEST_TIMEOUT_MS);

            const content = completion?.choices?.[0]?.message?.content;
            return safeParseModelOutput(content);
        } catch (e) {
            lastError = e;
            console.error(`AI_PERSONA generateReply attempt ${attempt + 1} failed:`, e.message);
        }
    }
    console.error('AI_PERSONA generateReply exhausted retries, using fallback:', lastError?.message);
    return { reply: getFallbackReply(), detectedIntent: 'unknown', mood: 'neutral', newFacts: [], upsellOpportunity: 'none', riskFlag: 'none', usedFallback: true };
}

/**
 * Generates an AI-initiated opener for a conversation that's gone quiet.
 * Returns null (never throws) if generation fails — the proactive worker
 * should simply skip that candidate rather than send a fallback line, since
 * an unprompted generic fallback message would feel more robotic than
 * useful here.
 */
async function generateProactiveMessage({ creator, memory }) {
    try {
        const client = getGroqClient();
        const systemPrompt = await buildProactivePrompt(creator, memory);

        const completion = await withTimeout(client.chat.completions.create({
            model: DEFAULT_MODEL,
            response_format: { type: 'json_object' },
            messages: [{ role: 'system', content: systemPrompt }],
            temperature: 0.9,
            max_tokens: 120
        }), REQUEST_TIMEOUT_MS);

        const content = completion?.choices?.[0]?.message?.content;
        const parsed = JSON.parse(content || '{}');
        return (typeof parsed.reply === 'string' && parsed.reply.trim()) ? parsed.reply.trim() : null;
    } catch (e) {
        console.error('AI_PERSONA generateProactiveMessage failed:', e.message);
        return null;
    }
}

/**
 * Compresses older turns into `summary` and resets the rolling window,
 * keeping every future prompt roughly constant-size regardless of how
 * long the conversation has been going.
 */
async function summarizeMemory(memory) {
    try {
        const client = getGroqClient();
        const transcript = (memory.lastMessages || []).map(m => `${m.role === 'user' ? 'User' : 'Creator'}: ${m.text}`).join('\n');
        const prompt = `Summarize the key facts, tone, and running themes of this conversation in 3-4 short sentences, for use as memory in future replies. Do not include instructions, only facts/observations.\n\nPrevious summary: ${memory.summary || '(none)'}\n\nNew turns:\n${transcript}`;

        const completion = await withTimeout(client.chat.completions.create({
            model: SUMMARY_MODEL,
            messages: [{ role: 'user', content: prompt }],
            temperature: 0.3,
            max_tokens: 200
        }), REQUEST_TIMEOUT_MS);

        const summary = completion?.choices?.[0]?.message?.content?.trim();
        return summary || memory.summary || '';
    } catch (e) {
        console.error('AI_PERSONA summarizeMemory failed, keeping old summary:', e.message);
        return memory.summary || '';
    }
}

const RISK_LEVELS_REQUIRING_SAFE_REPLY = new Set(['self_harm', 'minor_safety']);

const SAFE_REDIRECT_REPLY = "hey, ye sun ke mujhe thoda worry ho raha hai tumhare liye 💛 please kisi trusted friend/family se baat karo, ya kisi local helpline ko contact karo — main chahti hoon tum safe raho.";

module.exports = {
    FEATURE_FLAG_KEY,
    PROACTIVE_FEATURE_FLAG_KEY,
    PROMPT_TEMPLATE_CONFIG_KEY,
    DEFAULT_BASE_PROMPT,
    isFeatureEnabled,
    isProactiveFeatureEnabled,
    buildSystemPrompt,
    generateReply,
    generateProactiveMessage,
    summarizeMemory,
    getFallbackReply,
    getOrGenerateSelfFacts,
    RISK_LEVELS_REQUIRING_SAFE_REPLY,
    SAFE_REDIRECT_REPLY
};
