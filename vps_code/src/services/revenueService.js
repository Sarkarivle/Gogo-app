const PaymentTransaction = require('../models/PaymentTransaction');
const Subscription = require('../models/Subscription');
const User = require('../models/User');

class RevenueService {
    constructor() {
        this.io = null;
    }

    init(io) {
        this.io = io;
        console.log('💰 Revenue Service Optimized');

        // Broadcast financial updates every 30 seconds (Increased from 5s)
        setInterval(() => this.broadcastFinancials(), 30000);
    }

    async trackPaymentEvent(type, data) {
        // Broadcast immediate activity
        if (this.io) {
            this.io.emit('finance_activity', {
                type,
                ...data,
                timestamp: new Date()
            });
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
        const start = new Date(); start.setHours(0,0,0,0);
        const end = new Date(); end.setHours(23,59,59,999);

        const result = await PaymentTransaction.aggregate([
            { $match: { status: 'SUCCESS', createdAt: { $gte: start, $lte: end } } },
            { $group: { _id: null, total: { $sum: '$amount' }, count: { $sum: 1 } } }
        ]);
        return result.length > 0 ? result[0] : { total: 0, count: 0 };
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
        try {
            const startOfDay = new Date(); startOfDay.setHours(0,0,0,0);
            const startOfMonth = new Date(); startOfMonth.setDate(1); startOfMonth.setHours(0,0,0,0);

            const [gross, today, monthly, activePremium, totalUsers, failedToday, recentTransactions] = await Promise.all([
                this.getGrossRevenue().catch(e => 0),
                this.getTodayEarnings().catch(e => ({ total: 0, count: 0 })),
                this.getMonthlyRevenue().catch(e => 0),
                User.countDocuments({ isPremium: true }).catch(e => 0),
                User.estimatedDocumentCount().catch(e => 0),
                PaymentTransaction.countDocuments({
                    status: 'FAILED',
                    createdAt: { $gte: startOfDay }
                }).catch(e => 0),
                PaymentTransaction.find({})
                    .sort({ createdAt: -1 })
                    .limit(5)
                    .select('userPhone amount status gateway createdAt')
                    .lean()
                    .catch(e => [])
            ]);

            const arpu = totalUsers > 0 ? (gross / totalUsers).toFixed(2) : 0;
            const conversionRate = totalUsers > 0 ? ((activePremium / totalUsers) * 100).toFixed(1) : 0;

            // Gateway performance - Simplified
            let gatewayStats = [];

            return {
                grossRevenue: gross,
                todayEarnings: today.total || 0,
                todaySales: today.count || 0,
                monthlyRevenue: monthly,
                activePremiumUsers: activePremium,
                failedToday,
                arpu,
                conversionRate,
                recentTransactions,
                planBreakdown: [], // Reverted to empty for stability
                topGateway: (gatewayStats && gatewayStats.length > 0) ? gatewayStats[0]._id : 'N/A',
                subscriptionHealth: {
                    active: activePremium,
                    churnRate: '2.4%'
                }
            };
        } catch (error) {
            console.error("Critical Revenue Error:", error);
            throw error;
        }
    }

    async broadcastFinancials() {
        if (!this.io) return;
        try {
            // Check if there are any admins connected
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
