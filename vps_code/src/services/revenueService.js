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
                PaymentTransaction.find({ status: { $ne: 'PENDING' } })
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
        const finalQuery = { ...query, status: { $ne: 'PENDING' } };
        const skip = (page - 1) * limit;
        const [transactions, total] = await Promise.all([
            PaymentTransaction.find(finalQuery).sort({ createdAt: -1 }).skip(skip).limit(limit),
            PaymentTransaction.countDocuments(finalQuery)
        ]);
        return { transactions, total, page, pages: Math.ceil(total / limit) };
    }

    async getGooglePlayFullDashboard(page = 1, limit = 20, filters = {}) {
        const startOfToday = new Date(); startOfToday.setHours(0, 0, 0, 0);
        const endOfToday = new Date(); endOfToday.setHours(23, 59, 59, 999);
        const thirtyDaysAgo = new Date(); thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

        // --- NEW FLEXIBLE DATE FILTER LOGIC ---
        let dateQuery = { gateway: 'google_play', status: 'SUCCESS' };

        if (filters.range && filters.range !== 'All Time') {
            const now = new Date();
            let start = new Date();
            let end = new Date();

            switch (filters.range) {
                case 'Today':
                    start.setHours(0, 0, 0, 0);
                    dateQuery.createdAt = { $gte: start };
                    break;
                case 'Yesterday':
                    start.setDate(now.getDate() - 1); start.setHours(0, 0, 0, 0);
                    end.setDate(now.getDate() - 1); end.setHours(23, 59, 59, 999);
                    dateQuery.createdAt = { $gte: start, $lte: end };
                    break;
                case 'Last 7 Days':
                    start.setDate(now.getDate() - 7); start.setHours(0, 0, 0, 0);
                    dateQuery.createdAt = { $gte: start };
                    break;
                case 'This Month':
                    start.setDate(1); start.setHours(0, 0, 0, 0);
                    dateQuery.createdAt = { $gte: start };
                    break;
                case 'Last Month':
                    start.setMonth(now.getMonth() - 1); start.setDate(1); start.setHours(0, 0, 0, 0);
                    end.setMonth(now.getMonth()); end.setDate(0); end.setHours(23, 59, 59, 999);
                    dateQuery.createdAt = { $gte: start, $lte: end };
                    break;
                case 'Custom Range':
                    if (filters.startDate && filters.endDate) {
                        dateQuery.createdAt = {
                            $gte: new Date(filters.startDate),
                            $lte: new Date(new Date(filters.endDate).setHours(23, 59, 59, 999))
                        };
                    }
                    break;
            }
        } else if (filters.startDate && filters.endDate) {
            // Fallback for legacy date filter
            dateQuery.createdAt = {
                $gte: new Date(filters.startDate),
                $lte: new Date(new Date(filters.endDate).setHours(23, 59, 59, 999))
            };
        }

        // List of test phones to exclude
        const testPhones = ['+919999999999', '9999999999', '1234567890', '+911234567890'];

        // Helper to match "Test" in metadata or product name
        const testMatch = {
            $nor: [
                { userPhone: { $in: testPhones } },
                { 'metadata.isTest': true },
                { 'metadata.purchaseType': 0 }, // 0 = Test purchase in Google Play
                { 'metadata.productId': { $regex: /test/i } },
                { 'metadata.orderId': { $regex: /test/i } },
                { 'paymentMethod': { $regex: /test/i } },
                { 'metadata.productName': { $regex: /test/i } }
            ]
        };

        const finalMatch = { ...dateQuery, ...testMatch };

        // Get recent successful GP transactions to find "Real" users
        const recentGPTransactions = await PaymentTransaction.find(finalMatch).sort({ createdAt: -1 }).limit(200);
        const gpUserPhones = [...new Set(recentGPTransactions.map(tx => tx.userPhone))];

        const [summary, trend, cityStats, hourlyStats, usersRaw, totalUsers, alerts] = await Promise.all([
            // 1. Summary Stats
            PaymentTransaction.aggregate([
                { $match: finalMatch },
                {
                    $facet: {
                        lifetime: [{ $group: { _id: null, total: { $sum: '$amount' } } }],
                        today: [
                            { $match: { createdAt: { $gte: startOfToday } } },
                            { $group: { _id: null, total: { $sum: '$amount' } } }
                        ]
                    }
                }
            ]),
            // 2. Revenue Trend
            PaymentTransaction.aggregate([
                { $match: { ...finalMatch, createdAt: { $gte: thirtyDaysAgo } } },
                {
                    $group: {
                        _id: { $dateToString: { format: "%Y-%m-%d", date: "$createdAt" } },
                        dailyTotal: { $sum: "$amount" }
                    }
                },
                { $sort: { _id: 1 } }
            ]),
            // 3. City-wise Earning
            PaymentTransaction.aggregate([
                { $match: finalMatch },
                { $lookup: { from: 'users', localField: 'userPhone', foreignField: 'phone', as: 'userDetails' } },
                { $unwind: '$userDetails' },
                { $group: { _id: '$userDetails.city', total: { $sum: '$amount' } } },
                { $sort: { total: -1 } },
                { $limit: 5 }
            ]),
            // 4. Hourly Heatmap
            PaymentTransaction.aggregate([
                { $match: finalMatch },
                { $group: { _id: { $hour: "$createdAt" }, total: { $sum: "$amount" }, count: { $sum: 1 } } },
                { $sort: { _id: 1 } }
            ]),
            // 5. User List (Sorted by Purchase Date)
            User.find({
                $or: [
                    { phone: { $in: gpUserPhones } },
                    { 'subscription.paymentMethod': 'google_play' }
                ],
                phone: { $nin: testPhones },
                'subscription.id': { $not: /test/i }
            })
                .select('name phone city isPremium subscription premiumPlan createdAt')
                .sort({ 'subscription.lastPaymentDate': -1, 'subscription.startDate': -1 })
                .skip((page - 1) * limit)
                .limit(limit)
                .lean(),
            User.countDocuments({
                $or: [
                    { phone: { $in: gpUserPhones } },
                    { 'subscription.paymentMethod': 'google_play' }
                ],
                phone: { $nin: testPhones }
            }),
            // 6. Marketing Alerts
            User.aggregate([
                { $match: {
                    $or: [
                        { phone: { $in: gpUserPhones } },
                        { 'subscription.paymentMethod': 'google_play' }
                    ],
                    phone: { $nin: testPhones }
                } },
                {
                    $facet: {
                        activePremium: [{ $match: { isPremium: true } }, { $count: 'count' }],
                        cancelled: [{ $match: { 'subscription.status': 'cancelled' } }, { $count: 'count' }],
                        activeMandates: [{ $match: { 'subscription.status': 'active', 'subscription.autoRenew': true } }, { $count: 'count' }],
                        gracePeriod: [{ $match: { 'subscription.status': { $in: ['payment_pending', 'on_hold'] } } }, { $count: 'count' }],
                        failedToday: [
                            { $lookup: { from: 'paymenttransactions', localField: 'phone', foreignField: 'userPhone', as: 'txs' } },
                            { $unwind: '$txs' },
                            { $match: { 'txs.gateway': 'google_play', 'txs.status': 'FAILED', 'txs.createdAt': { $gte: startOfToday } } },
                            { $count: 'count' }
                        ]
                    }
                }
            ])
        ]);

        const stats = summary[0] || { lifetime: [], today: [] };
        const mAlerts = alerts[0] || { activePremium: [], cancelled: [], activeMandates: [], failedToday: [] };

        return {
            summary: {
                lifetimeEarnings: stats.lifetime?.[0]?.total || 0,
                todayEarnings: stats.today?.[0]?.total || 0,
                activePremium: mAlerts.activePremium?.[0]?.count || 0,
                cancelled: mAlerts.cancelled?.[0]?.count || 0,
                activeMandates: mAlerts.activeMandates?.[0]?.count || 0,
                gracePeriod: mAlerts.gracePeriod?.[0]?.count || 0,
                failedToday: mAlerts.failedToday?.[0]?.count || 0
            },
            analytics: {
                trend: trend || [],
                topCities: cityStats || [],
                hourlyHeatmap: hourlyStats || []
            },
            users: usersRaw || [],
            pagination: {
                total: totalUsers || 0,
                page,
                pages: totalUsers ? Math.ceil(totalUsers / limit) : 0
            }
        };
    }
}

module.exports = new RevenueService();
