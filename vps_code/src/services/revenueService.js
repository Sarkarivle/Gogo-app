const PaymentTransaction = require('../models/PaymentTransaction');
const Subscription = require('../models/Subscription');
const User = require('../models/User');

class RevenueService {
    constructor() {
        this.io = null;
        this.redis = null;
        this.cachedMetrics = null;
        this.lastFetchTime = 0;
        this.CACHE_TTL = 30000; // 30 seconds
    }

    init(io, redisClient) {
        this.io = io;
        this.redis = redisClient;
        console.log('💰 Revenue Service Optimized with Redis');

        // Broadcast financial updates every 20 seconds for real-time feel
        setInterval(() => this.broadcastFinancials(), 20000);
    }

    async trackPaymentEvent(type, data) {
        // Invalidate cache on new payment events to ensure next fetch is fresh
        this.lastFetchTime = 0;

        if (this.io) {
            this.io.to('admin').emit('finance_activity', {
                type,
                ...data,
                timestamp: new Date()
            });
        }

        // If it's a success, we can also update immediate Redis counters for Today's earnings
        if (type === 'PAYMENT_SUCCESS' && data.amount && this.redis) {
            const today = new Date().toISOString().split('T')[0];
            await this.redis.hIncrBy(`finance:stats:${today}`, 'earnings', Math.floor(data.amount));
            await this.redis.hIncrBy(`finance:stats:${today}`, 'count', 1);
        }
    }

    async getGrossRevenue() {
        const result = await PaymentTransaction.aggregate([
            { $match: { status: 'SUCCESS' } },
            { $group: { _id: null, total: { $sum: '$amount' } } }
        ]);
        return result.length > 0 ? result[0].total : 0;
    }

    async getTodayEarnings() {
        const today = new Date().toISOString().split('T')[0];

        // Try Redis first for instant feedback
        if (this.redis) {
            const data = await this.redis.hGetAll(`finance:stats:${today}`);
            if (data && data.earnings) {
                return { total: parseInt(data.earnings), count: parseInt(data.count || 0) };
            }
        }

        const start = new Date(); start.setHours(0,0,0,0);
        const end = new Date(); end.setHours(23,59,59,999);

        const result = await PaymentTransaction.aggregate([
            { $match: { status: 'SUCCESS', createdAt: { $gte: start, $lte: end } } },
            { $group: { _id: null, total: { $sum: '$amount' }, count: { $sum: 1 } } }
        ]);

        const stats = result.length > 0 ? { total: result[0].total, count: result[0].count } : { total: 0, count: 0 };

        // Seed Redis
        if (this.redis) {
            await this.redis.hSet(`finance:stats:${today}`, {
                earnings: stats.total.toString(),
                count: stats.count.toString()
            });
            await this.redis.expire(`finance:stats:${today}`, 86400);
        }

        return stats;
    }

    async getMonthlyRevenue() {
        const start = new Date(); start.setDate(1); start.setHours(0,0,0,0);
        const result = await PaymentTransaction.aggregate([
            { $match: { status: 'SUCCESS', createdAt: { $gte: start } } },
            { $group: { _id: null, total: { $sum: '$amount' } } }
        ]);
        return result.length > 0 ? result[0].total : 0;
    }

    async getFinancialMetrics() {
        // Simple memory cache with short TTL to prevent DB hammering
        const now = Date.now();
        if (this.cachedMetrics && (now - this.lastFetchTime < this.CACHE_TTL)) {
            return this.cachedMetrics;
        }

        try {
            const startOfDay = new Date(); startOfDay.setHours(0,0,0,0);

            const [gross, today, monthly, activePremium, totalUsers, failedToday, recentTransactions] = await Promise.all([
                this.getGrossRevenue().catch(() => 0),
                this.getTodayEarnings().catch(() => ({ total: 0, count: 0 })),
                this.getMonthlyRevenue().catch(() => 0),
                User.countDocuments({ isPremium: true }).catch(() => 0),
                User.estimatedDocumentCount().catch(() => 0),
                PaymentTransaction.countDocuments({
                    status: 'FAILED',
                    createdAt: { $gte: startOfDay }
                }).catch(() => 0),
                PaymentTransaction.find({})
                    .sort({ createdAt: -1 })
                    .limit(5)
                    .select('userPhone amount status gateway createdAt')
                    .lean()
                    .catch(() => [])
            ]);

            const arpu = totalUsers > 0 ? (gross / totalUsers).toFixed(2) : 0;
            const conversionRate = totalUsers > 0 ? ((activePremium / totalUsers) * 100).toFixed(1) : 0;

            this.cachedMetrics = {
                grossRevenue: gross,
                todayEarnings: today.total || 0,
                todaySales: today.count || 0,
                monthlyRevenue: monthly,
                activePremiumUsers: activePremium,
                failedToday,
                arpu,
                conversionRate,
                recentTransactions,
                subscriptionHealth: {
                    active: activePremium,
                    churnRate: '2.4%'
                },
                timestamp: new Date()
            };
            this.lastFetchTime = now;
            return this.cachedMetrics;
        } catch (error) {
            console.error("Critical Revenue Error:", error);
            return this.cachedMetrics || {};
        }
    }

    async broadcastFinancials() {
        if (!this.io) return;
        try {
            const adminRoom = this.io.sockets.adapter.rooms.get('admin');
            if (!adminRoom || adminRoom.size === 0) return;

            const metrics = await this.getFinancialMetrics();
            this.io.to('admin').emit('admin_revenue_update', metrics);
        } catch (e) {
            console.error('Revenue Broadcast Error:', e);
        }
    }

    async getPaymentHistory(query = {}, page = 1, limit = 20) {
        const skip = (page - 1) * limit;
        const [transactions, total] = await Promise.all([
            PaymentTransaction.find(query).sort({ createdAt: -1 }).skip(skip).limit(limit),
            PaymentTransaction.countDocuments(query)
        ]);
        return { transactions, total, page, pages: Math.ceil(total / limit) };
    }
}

module.exports = new RevenueService();
