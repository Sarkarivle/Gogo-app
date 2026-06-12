const User = require('../models/User');
const Message = require('../models/Message');
const Report = require('../models/Report');
const AnalyticsEvent = require('../models/AnalyticsEvent');
const os = require('os');
const https = require('https');

const normalize = (p) => {
    if (!p) return '';
    const clean = String(p).replace(/[^0-9]/g, '');
    return clean.length >= 10 ? clean.slice(-10) : clean;
};

class AnalyticsService {
    constructor() {
        this.io = null;
        this.redis = null;
        this.metrics = {
            activeSockets: 0,
            onlineUsers: 0,
            messagesLastMinute: 0,
            eventThroughput: 0,
            activeCalls: 0,
            activeAdmins: 0,

            liveActivity: {
                app_open: 0,
                login_page_open: 0,
                otp_verified: 0,
                registration: 0,
                onboarding_completed: 0,
                unregistered_today: 0,
                trial_page_open: 0,
                payment_started: 0,
                premium_activated: 0
            },

            minuteActivity: {
                app_open: 0,
                login_page_open: 0,
                trial_page_open: 0,
                premium_activated: 0
            },

            uniqueFunnel: {
                app_open: 0,
                login_page_open: 0,
                otp_verified: 0,
                onboarding_completed: 0,
                trial_page_open: 0,
                premium_activated: 0
            }
        };
    }

    init(io, redisClient) {
        this.io = io;
        this.redis = redisClient;
        console.log('📊 Analytics Service Optimized with Redis');

        // Initial load of unique funnel metrics from DB as fallback/base
        this.refreshUniqueMetrics();

        // Broadcast to admins every 10 seconds for more "real-time" feel
        setInterval(() => this.broadcastMetrics(), 10000);

        // Periodically refresh from Redis to keep local cache updated
        setInterval(() => this.syncMetricsFromRedis(), 5000);

        // Refresh unique metrics from DB periodically (every 30 mins as fallback)
        setInterval(() => this.refreshUniqueMetrics(), 1800000);
    }

    async syncMetricsFromRedis() {
        if (!this.redis) return;

        try {
            const today = new Date().toISOString().split('T')[0];
            const currentMinute = Math.floor(Date.now() / 60000);

            // 1. Sync Live Activity (Daily Totals)
            const liveActivityKeys = Object.keys(this.metrics.liveActivity);
            const liveData = await this.redis.hGetAll(`analytics:live_activity:${today}`);
            liveActivityKeys.forEach(key => {
                this.metrics.liveActivity[key] = parseInt(liveData[key] || 0);
            });

            // 2. Sync Minute Activity (Throughput)
            const minuteActivityKeys = Object.keys(this.metrics.minuteActivity);
            const minuteData = await Promise.all(minuteActivityKeys.map(key =>
                this.redis.get(`analytics:minute_activity:${key}:${currentMinute}`)
            ));
            minuteActivityKeys.forEach((key, i) => {
                this.metrics.minuteActivity[key] = parseInt(minuteData[i] || 0);
            });

            // 3. Sync Unique Funnel (HyperLogLog)
            const funnelKeys = Object.keys(this.metrics.uniqueFunnel);
            const funnelData = await Promise.all(funnelKeys.map(key =>
                this.redis.pfCount(`analytics:unique_funnel:${key}`)
            ));
            funnelKeys.forEach((key, i) => {
                this.metrics.uniqueFunnel[key] = funnelData[i];
            });

            // 4. Sync Other Counters
            const [msgCount, eventCount, callCount, onlineCount, adminCount] = await Promise.all([
                this.redis.get(`analytics:messages_minute:${currentMinute}`),
                this.redis.get(`analytics:events_minute:${currentMinute}`),
                this.redis.sCard('analytics:active_calls'),
                this.redis.sCard('online_users'),
                this.redis.sCard('active_admins')
            ]);

            this.metrics.messagesLastMinute = parseInt(msgCount || 0);
            this.metrics.eventThroughput = parseInt(eventCount || 0);
            this.metrics.activeCalls = callCount;
            this.metrics.onlineUsers = onlineCount;
            this.metrics.activeAdmins = adminCount;

        } catch (e) {
            // console.error("Redis Sync Error:", e.message);
        }
    }

    async refreshUniqueMetrics() {
        try {
            // This is a slow operation, only used to seed/verify
            const steps = Object.keys(this.metrics.uniqueFunnel);
            // We don't overwrite if Redis is already populated
            // But we can use this to sync DB -> Redis if Redis is empty
            if (this.redis) {
                for (const step of steps) {
                    const count = await this.redis.pfCount(`analytics:unique_funnel:${step}`);
                    if (count === 0) {
                        // Seed Redis with existing distinctIds from DB (careful with memory if millions)
                        // For now, just trust Redis will accumulate from here on or use a migration script.
                    }
                }
            }
        } catch (e) {}
    }

    async trackEvent(type, distinctId, metadata = {}) {
        const dId = normalize(distinctId);
        const today = new Date().toISOString().split('T')[0];
        const currentMinute = Math.floor(Date.now() / 60000);

        if (this.redis) {
            const multi = this.redis.multi();

            // 1. Update Live (Daily) Activity
            if (this.metrics.liveActivity[type] !== undefined) {
                multi.hIncrBy(`analytics:live_activity:${today}`, type, 1);
                multi.expire(`analytics:live_activity:${today}`, 172800); // 48h TTL
            }

            // Custom logic for Unregistered tracking
            if (type === 'registration') {
                multi.hIncrBy(`analytics:live_activity:${today}`, 'unregistered_today', 1);
            }

            // 2. Update Minute Rolling Window
            if (this.metrics.minuteActivity[type] !== undefined) {
                multi.incr(`analytics:minute_activity:${type}:${currentMinute}`);
                multi.expire(`analytics:minute_activity:${type}:${currentMinute}`, 120); // 2m TTL
            }

            // 3. Persistent Unique Tracking (HyperLogLog)
            if (dId && this.metrics.uniqueFunnel[type] !== undefined) {
                multi.pfAdd(`analytics:unique_funnel:${type}`, dId);
            }

            // 4. Global Event Throughput
            multi.incr(`analytics:events_minute:${currentMinute}`);
            multi.expire(`analytics:events_minute:${currentMinute}`, 120);

            await multi.exec().catch(() => {});
        }

        // Broadcast to monitoring stream if active
        if (this.io) {
            this.io.to('admin').emit('admin_live_event', {
                type: 'EVENT',
                label: type,
                phone: dId,
                timestamp: new Date()
            });
        }

        // Persistent DB storage (Keep for historical audit/deep analysis)
        if (dId) {
            const variations = [dId, `+91${dId}`, `91${dId}`];
            AnalyticsEvent.exists({ type, distinctId: { $in: variations } }).then(exists => {
                if (!exists) {
                    AnalyticsEvent.create({ type, distinctId: dId, metadata }).catch(() => {});
                }
            });
        }

        // Server-side Facebook Conversions API (CAPI)
        this.sendToFacebookCAPI(type, dId, metadata);
    }

    async trackPremiumUpgrade(distinctId, metadata = {}) {
        return await this.trackEvent('premium_activated', distinctId, metadata);
    }

    async sendToFacebookCAPI(type, distinctId, metadata = {}) {
        try {
            const MarketingConfig = require('../models/MarketingConfig');
            const config = await MarketingConfig.findOne({ key: 'global_settings' }).lean();

            if (!config || !config.isMetaEnabled || !config.fbPixelId || !config.fbAccessToken) return;
            if (!distinctId) return;

            const crypto = require('crypto');
            // Format phone for Facebook: ensure it has 91 if it's 10 digits
            let phoneToHash = distinctId.replace(/[^0-9]/g, '');
            if (phoneToHash.length === 10) phoneToHash = '91' + phoneToHash;

            const hashedPhone = crypto.createHash('sha256').update(phoneToHash).digest('hex');
            const externalId = crypto.createHash('sha256').update(distinctId).digest('hex');

            let clientIp = metadata.ip || "1.1.1.1";
            if (typeof clientIp === 'string') {
                if (clientIp.includes(',')) clientIp = clientIp.split(',')[0].trim();
                if (clientIp === '::1' || clientIp === '127.0.0.1' || clientIp.includes('localhost')) clientIp = '1.1.1.1';
            }

            let fbEventName = type;
            if (type === 'app_open') fbEventName = 'ActivateApp';
            else if (type === 'onboarding_completed') fbEventName = 'CompleteRegistration';
            else if (type === 'premium_activated') fbEventName = 'Purchase';
            else if (type === 'payment_started' || type === 'offer_payment_started') fbEventName = 'InitiateCheckout';
            else if (type === 'start_call') fbEventName = 'Contact';

            const url = `https://graph.facebook.com/v18.0/${config.fbPixelId}/events?access_token=${config.fbAccessToken}`;
            const payload = {
                data: [{
                    event_name: fbEventName,
                    event_time: metadata.timestamp || Math.floor(Date.now() / 1000),
                    event_id: metadata.event_id || "",
                    action_source: "app",
                    app_id: config.fbAppId,
                    user_data: {
                        ph: [hashedPhone],
                        external_id: externalId,
                        client_ip_address: clientIp,
                        client_user_agent: metadata.userAgent || "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36",
                        advertiser_tracking_enabled: 1,
                        application_tracking_enabled: 1
                    },
                    custom_data: {
                        value: metadata.amount || metadata.value || (fbEventName === 'Purchase' ? 199 : 0),
                        currency: metadata.currency || 'INR',
                        content_name: metadata.planId || 'Premium Access'
                    }
                }]
            };

            if (config.fbTestCode) payload.test_event_code = config.fbTestCode;

            // ACTUAL SENDING LOGIC (Using built-in https)
            const postData = JSON.stringify(payload);
            const options = {
                hostname: 'graph.facebook.com',
                path: `/v18.0/${config.fbPixelId}/events?access_token=${config.fbAccessToken}`,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': postData.length
                }
            };

            const fbReq = https.request(options, (fbRes) => {
                let resData = '';
                fbRes.on('data', (chunk) => resData += chunk);
                fbRes.on('end', () => {
                    if (fbRes.statusCode === 200) {
                        console.log(`🚀 [FB CAPI SUCCESS] Event "${fbEventName}" sent for ${distinctId}`);
                    } else {
                        console.error(`❌ [FB CAPI FAILED] Status: ${fbRes.statusCode}, Response: ${resData}`);
                    }
                });
            });

            fbReq.on('error', (err) => {
                console.error(`❌ [FB CAPI NETWORK ERROR]: ${err.message}`);
            });

            fbReq.write(postData);
            fbReq.end();

        } catch (e) {
            console.error("sendToFacebookCAPI Error:", e.message);
        }
    }

    trackMessage() {
        const currentMinute = Math.floor(Date.now() / 60000);
        const today = new Date().toISOString().split('T')[0];

        if (this.redis) {
            const multi = this.redis.multi();
            multi.incr(`analytics:messages_minute:${currentMinute}`);
            multi.expire(`analytics:messages_minute:${currentMinute}`, 120);
            multi.incr(`analytics:messages_today:${today}`);
            multi.expire(`analytics:messages_today:${today}`, 172800);
            multi.exec().catch(() => {});
        }

        if (this.io) {
            this.io.to('admin').emit('admin_live_event', {
                type: 'MESSAGE',
                label: 'New Message',
                timestamp: new Date()
            });
        }
    }

    trackCallStart(roomId) {
        if (roomId && this.redis) {
            this.redis.sAdd('analytics:active_calls', roomId).catch(() => {});
            if (this.io) {
                this.io.to('admin').emit('admin_live_event', {
                    type: 'CALL_START',
                    label: 'Call Started',
                    roomId,
                    timestamp: new Date()
                });
            }
        }
    }

    trackCallEnd(roomId) {
        if (roomId && this.redis) {
            this.redis.sRem('analytics:active_calls', roomId).catch(() => {});
        }
    }

    getServerHealth() {
        return {
            cpuUsage: (os.loadavg()[0] * 10).toFixed(2),
            freeMem: (os.freemem() / 1024 / 1024 / 1024).toFixed(2),
            totalMem: (os.totalmem() / 1024 / 1024 / 1024).toFixed(2),
            uptime: (os.uptime() / 3600).toFixed(1)
        };
    }

    async broadcastMetrics() {
        if (!this.io) return;

        try {
            const adminRoom = this.io.sockets.adapter.rooms.get('admin');
            if (!adminRoom || adminRoom.size === 0) return;

            const serverHealth = this.getServerHealth();

            const liveMetrics = {
                activeSockets: this.io.engine.clientsCount,
                onlineUsers: this.metrics.onlineUsers,
                activeCalls: this.metrics.activeCalls,
                activeAdmins: this.metrics.activeAdmins,
                unregisteredTotal: this.metrics.liveActivity.unregistered_total || 0, // Fallback if needed
                unregisteredToday: this.metrics.liveActivity.unregistered_today || 0,
                eventThroughput: `${(this.metrics.eventThroughput / 60).toFixed(1)}/sec`,
                messagesPerMin: this.metrics.messagesLastMinute,

                funnel: this.metrics.uniqueFunnel,
                liveActivity: this.metrics.liveActivity,
                minuteActivity: this.metrics.minuteActivity,

                serverHealth,
                timestamp: new Date()
            };

            this.io.to('admin').emit('admin_metrics_update', liveMetrics);
        } catch (e) {
            console.error('Analytics Broadcast Error:', e);
        }
    }

    async getLiveMonitoringData() {
        return {
            activeSockets: this.io ? this.io.engine.clientsCount : 0,
            onlineUsers: this.metrics.onlineUsers,
            activeCalls: this.metrics.activeCalls,
            activeAdmins: this.metrics.activeAdmins,
            eventThroughput: `${(this.metrics.eventThroughput / 60).toFixed(1)}/sec`,
            serverHealth: this.getServerHealth()
        };
    }

    async getDashboardStats() {
        // Sync one last time before returning full stats for a request
        await this.syncMetricsFromRedis();

        const todayStart = new Date(); todayStart.setHours(0,0,0,0);

        const [total, premium, onlineCount, pendingReports, totalMsgs, incomplete, unregisteredToday] = await Promise.all([
            User.estimatedDocumentCount(),
            User.countDocuments({ isPremium: true }),
            User.countDocuments({
                isOnline: true,
                $or: [{ hasCompletedOnboarding: true }, { dobYear: { $exists: true, $ne: null } }]
            }),
            Report.countDocuments({ status: 'Pending' }),
            Message.estimatedDocumentCount(),
            User.countDocuments({
                hasCompletedOnboarding: false,
                dobYear: { $exists: false }
            }),
            User.countDocuments({
                createdAt: { $gte: todayStart },
                hasCompletedOnboarding: false,
                dobYear: { $exists: false }
            })
        ]);

        const maleCount = await User.countDocuments({ gender: 'Male', hasCompletedOnboarding: true });
        const femaleCount = await User.countDocuments({ gender: 'Female', hasCompletedOnboarding: true });

        const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
        const dau = await User.countDocuments({ lastSeen: { $gte: dayAgo } });

        const uf = this.metrics.uniqueFunnel;
        const onboardingConv = uf.app_open > 0 ? Math.round((uf.onboarding_completed / uf.app_open) * 100) : 0;
        const trialConv = uf.onboarding_completed > 0 ? Math.round((uf.trial_page_open / uf.onboarding_completed) * 100) : 0;
        const premiumConv = uf.trial_page_open > 0 ? Math.round((uf.premium_activated / uf.trial_page_open) * 100) : 0;
        const overallROI = uf.app_open > 0 ? ((uf.premium_activated / uf.app_open) * 100).toFixed(1) : "0.0";

        const avgMessagesPerUser = total > 0 ? (totalMsgs / total).toFixed(1) : 0;

        return {
            totalUsers: total,
            incompleteUsers: incomplete, // This is unregisteredTotal
            unregisteredTotal: incomplete,
            unregisteredToday: unregisteredToday,
            premiumUsers: premium,
            onlineUsers: onlineCount, // Filtered online count
            activeCalls: this.metrics.activeCalls,
            activeAdmins: this.metrics.activeAdmins,
            totalMessages: totalMsgs,
            pendingReports,
            dau,
            mau: Math.floor(total * 0.8),
            avgMessagesPerUser,
            genderRatio: { male: maleCount, female: femaleCount },
            funnelMetrics: {
                onboardingConv,
                trialConv,
                premiumConv,
                overallROI
            },
            funnelRaw: uf,
            liveActivity: this.metrics.liveActivity,
            serverHealth: this.getServerHealth(),
            systemStatus: 'ONLINE'
        };
    }
}

module.exports = new AnalyticsService();
