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
        const [gross, today, monthly, activePremium, totalUsers, failedToday] = await Promise.all([
            this.getGrossRevenue(),
            this.getTodayEarnings(),
            this.getMonthlyRevenue(),
            User.countDocuments({ isPremium: true }),
            User.countDocuments(),
            PaymentTransaction.countDocuments({
                status: 'FAILED',
                createdAt: { $gte: new Date(new Date().setHours(0,0,0,0)) }
            })
        ]);

        const arpu = totalUsers > 0 ? (gross / totalUsers).toFixed(2) : 0;

        // Gateway performance
        const gatewayStats = await PaymentTransaction.aggregate([
            { $match: { status: 'SUCCESS' } },
            { $group: { _id: '$gateway', count: { $sum: 1 }, total: { $sum: '$amount' } } },
            { $sort: { total: -1 } }
        ]);

        return {
            grossRevenue: gross,
            todayEarnings: today.total,
            todaySales: today.count,
            monthlyRevenue: monthly,
            activePremiumUsers: activePremium,
            failedToday,
            arpu,
            topGateway: gatewayStats.length > 0 ? gatewayStats[0]._id : 'N/A',
            subscriptionHealth: {
                active: activePremium,
                churnRate: '2.4%' // Example calculation would go here
            }
        };
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
