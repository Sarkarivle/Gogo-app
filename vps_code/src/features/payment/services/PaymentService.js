const Config = require('../../../shared/models/Config');
const RazorpayProvider = require('./RazorpayProvider');
const PhonePeProvider = require('./PhonePeProvider');
const CashfreeProvider = require('./CashfreeProvider');
const GooglePlayProvider = require('./GooglePlayProvider');
const PaymentTransaction = require('../models/PaymentTransaction');
const User = require('../../users/models/User');
const analyticsService = require('../../../shared/services/analyticsService');
const revenueService = require('./revenueService');
const { normalize, phoneQuery } = require('../../../shared/utils/phoneUtils');

class PaymentService {
    static async _findMatchingOffer(transaction) {
        try {
            const offerConfig = await Config.findOne({ key: 'special_offers' });
            const offers = offerConfig?.value?.offers || [];
            if (!offers.length) return null;

            const metadata = transaction.metadata || {};
            const ids = [
                metadata.productId,
                metadata.offerId,
                metadata.planId,
                transaction.orderId,
                transaction.gatewaySubscriptionId
            ].filter(Boolean).map(String);

            return offers.find(o =>
                ids.some(id =>
                    o.id === id ||
                    o.rzpPlanId === id ||
                    o.googlePlayId === id ||
                    o.googlePlaySubId === id
                ) ||
                (transaction.amount && Number(o.price) === Number(transaction.amount))
            ) || null;
        } catch (e) {
            console.error("Offer lookup error:", e);
            return null;
        }
    }

    static async getProvider(gatewayName) {
        const config = await Config.findOne({ key: 'payment_settings' });

        if (!config || !config.value) {
            console.error("❌ CRITICAL: 'payment_settings' missing in MongoDB Config collection.");
            throw new Error("Payment settings not configured in database.");
        }

        const settings = config.value;
        const gateway = (gatewayName || settings.activeGateway || '').toLowerCase();

        if (!gateway) {
            throw new Error("No active payment gateway selected in settings.");
        }

        const gatewayConfig = settings[gateway];
        if (gateway !== 'google_play' && !gatewayConfig) {
            console.error(`❌ ERROR: Configuration for gateway '${gateway}' is undefined in DB.`);
            throw new Error(`Payment gateway '${gateway}' is selected but its credentials are missing.`);
        }

        switch (gateway) {
            case 'razorpay':
                return new RazorpayProvider(gatewayConfig);
            case 'phonepe':
                return new PhonePeProvider(gatewayConfig);
            case 'cashfree':
                return new CashfreeProvider(gatewayConfig);
            case 'google_play':
                const gpConfig = await Config.findOne({ key: 'google_play_settings' });
                return new GooglePlayProvider(gpConfig ? gpConfig.value : (settings.google_play || {}));
            default:
                throw new Error(`Unsupported gateway: ${gateway}`);
        }
    }

    static async createOrder(phone, preferredGateway, overrides = {}) {
        try {
            const normalizedPhone = normalize(phone);
            const provider = await this.getProvider(preferredGateway);

            const offerConfig = await Config.findOne({ key: 'special_offers' });
            const offers = offerConfig?.value?.offers || [];

            const user = await User.findOne(phoneQuery(normalizedPhone));
            const hasUsedTrial = user?.subscription?.hasUsedTrial || false;

            let selectedOffer;
            if (offers && offers.length > 0) {
                // ALWAYS prioritize Offer #1 (index 0) from Admin Panel for trial/main flow
                // This ensures IDs like 'gogo_monthly_199' and 'gogo-17-rs-offer' are used correctly
                selectedOffer = offers[0];

                // Only use other offers if a specific amount/offerId is NOT requested
                // and user has already used trial. But for Google Play, we mostly want the main product.
                if (hasUsedTrial && !overrides.amount && !overrides.offerId) {
                    selectedOffer = offers[2] || offers[0];
                }
            }

            let amount = overrides.amount || selectedOffer?.price || 199;
            if (isNaN(amount) || amount <= 0) amount = 199; // Fallback for invalid amount

            const gateway = (preferredGateway || '').toLowerCase();
            const isSubscription = overrides.isSubscription === true;
            let planId = overrides.offerId || selectedOffer?.rzpPlanId || selectedOffer?.id || `offer_${amount}`;

            if (isSubscription && gateway === 'razorpay' && !selectedOffer?.rzpPlanId && !overrides.offerId) {
                console.error("❌ ERROR: No Razorpay subscription planId found. Direct payments do not need this.");
                throw new Error("Razorpay subscription plan ID is missing. Use direct payment or add a valid Razorpay plan ID.");
            }

            let duration = overrides.duration || selectedOffer?.duration || 30;

            let googlePlayId = (overrides.googlePlayId || selectedOffer?.googlePlayId || '').toString().trim();
            let googlePlaySubId = (overrides.googlePlaySubId || selectedOffer?.googlePlaySubId || '').toString().trim();

            // SPECIAL RULE: If using Google Play, and IDs are missing from overrides,
            // ALWAYS force Offer #1 IDs (index 0) if they exist.
            if (gateway === 'google_play' && !overrides.googlePlayId && offers && offers[0]) {
                googlePlayId = (offers[0].googlePlayId || '').toString().trim();
                googlePlaySubId = (offers[0].googlePlaySubId || '').toString().trim();
                console.log(`🎯 Google Play ID Forced from Offer #1: ${googlePlayId}`);
            }

            if (gateway === 'google_play' && !googlePlaySubId) {
                googlePlaySubId = googlePlayId;
            }

            const orderData = await provider.createOrder({
                phone: normalizedPhone,
                amount,
                isSubscription,
                isTrial: amount < 10,
                overridePlanId: planId,
                productId: googlePlayId,
                googlePlaySubId: googlePlaySubId
            });

            if (orderData.success && orderData.orderId && preferredGateway !== 'google_play') {
                await PaymentTransaction.create({
                    orderId: orderData.orderId,
                    userPhone: normalizedPhone,
                    gateway: orderData.gateway,
                    amount: amount,
                    status: 'PENDING',
                    metadata: { ...orderData, duration, offerId: planId, isFirstTime: !hasUsedTrial }
                });
            }
            return orderData;
        } catch (error) {
            console.error("Order Creation Failed:", error);
            const errorMessage = error.message || (typeof error === 'object' ? JSON.stringify(error) : String(error));
            return { success: false, message: errorMessage };
        }
    }

    static async _updateUserSubscription(phone, transaction, method, io) {
        const now = new Date();
        const normalizedPhone = normalize(phone);
        const user = await User.findOne(phoneQuery(normalizedPhone));
        if (!user) return null;

        const transactionId = transaction.orderId || transaction.gatewayTransactionId || transaction.paymentId;
        if (!transactionId) return user;

        const isGoogle = transaction.gateway === 'google_play' || String(transactionId).startsWith('GPA.');
        const isRazorpay = transaction.gateway === 'razorpay' || (method || '').toLowerCase().includes('upi');
        const isRenewal = isGoogle && transactionId.includes('..');
        const isTrial = !isRenewal && (transaction.metadata?.paymentState === 2 || transaction.amount < 10);

        const matchedOffer = await this._findMatchingOffer(transaction);

        // Call-credit packs are a separate currency from premium/subscription
        // — handled in their own small, self-contained branch so none of the
        // premium-specific logic below (expiry math, existing-history
        // correction, subscription status) is ever touched by a credits buy.
        if (matchedOffer?.type === 'credits') {
            const alreadyCredited = user.paymentHistory.some(h => h.orderId === transactionId);
            if (alreadyCredited) return user; // idempotent — don't double-credit on webhook retries
            const updatedUser = await User.findOneAndUpdate(
                { _id: user._id },
                {
                    $inc: { callCredits: matchedOffer.credits || 0 },
                    $push: {
                        paymentHistory: {
                            orderId: transactionId,
                            paymentId: transaction.gatewayTransactionId || transaction.paymentId,
                            amount: transaction.amount || 0,
                            status: 'SUCCESS',
                            method: method || 'UPI',
                            timestamp: now
                        }
                    }
                },
                { new: true }
            );
            if (io) io.to(`user_${normalizedPhone}`).emit('call_credits_refresh', { callCredits: updatedUser.callCredits });
            return updatedUser;
        }

        let planName = matchedOffer?.name || (isTrial ? `Trial Gold` : 'Premium Gold');

        let newExpiry;
        const providerNextBill = transaction.current_period_end || transaction.next_billing_at || transaction.start_at;
        const offerDurationDays = transaction.metadata?.duration || matchedOffer?.duration;

        if (isGoogle && providerNextBill) {
            newExpiry = new Date(providerNextBill * 1000);
        } else if (isGoogle && transaction.metadata?.expiryTimeMillis) {
            newExpiry = new Date(parseInt(transaction.metadata.expiryTimeMillis));
        } else if (isRazorpay && offerDurationDays) {
            newExpiry = new Date(now.getTime() + (offerDurationDays * 24 * 60 * 60 * 1000));
        } else if (providerNextBill) {
            newExpiry = new Date(providerNextBill * 1000);
        } else {
            const durationDays = offerDurationDays || (isTrial ? 1 : 30);
            newExpiry = new Date(now.getTime() + (durationDays * 24 * 60 * 60 * 1000));
        }

        const subStatus = isTrial ? 'trial_active' : 'active';
        const currentAmount = transaction.amount || 0;

        const existingHistoryIndex = user.paymentHistory.findIndex(h =>
            h.orderId === transactionId ||
            (transaction.metadata?.temporaryOrderId && h.orderId === transaction.metadata.temporaryOrderId) ||
            (isGoogle && !isRenewal && h.purchaseToken === (transaction.metadata?.purchaseToken || transaction.gatewayTransactionId) && !h.orderId.startsWith('GPA.'))
        );

        if (existingHistoryIndex !== -1) {
            const existingEntry = user.paymentHistory[existingHistoryIndex];

            // AGGRESSIVE CORRECTION: Update amount and status even if already present
            console.log(`🔧 [Subscription Update] Syncing details for ${transactionId}: ₹${currentAmount}`);

            const updateSet = {
                premiumExpiry: newExpiry,
                'subscription.status': subStatus,
                'subscription.nextBillingDate': newExpiry,
                [`paymentHistory.${existingHistoryIndex}.status`]: 'SUCCESS',
                [`paymentHistory.${existingHistoryIndex}.amount`]: currentAmount,
                [`paymentHistory.${existingHistoryIndex}.orderId`]: transactionId,
                [`paymentHistory.${existingHistoryIndex}.expiryDate`]: newExpiry
            };

            // Only update premium access if it's current
            if (!user.isPremium || newExpiry > user.premiumExpiry) {
                updateSet.isPremium = true;
                updateSet.premiumPlan = planName;
            }

            const updateResult = await User.findOneAndUpdate(
                { _id: user._id, "paymentHistory.orderId": existingEntry.orderId },
                { $set: updateSet },
                { new: true }
            );

            // Recalculate Total Amount Paid safely
            const freshHistory = updateResult.paymentHistory;
            const newTotal = freshHistory.filter(h => h.status === 'SUCCESS').reduce((sum, h) => sum + (h.amount || 0), 0);
            await User.updateOne({ _id: user._id }, { $set: { 'subscription.totalAmountPaid': newTotal } });

            if (io) io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { isPremium: true, status: subStatus });
            return await User.findById(user._id);
        }

        // NEW SUCCESS TRANSACTION
        const updateFields = {
            isPremium: true,
            premiumExpiry: newExpiry,
            premiumPlan: planName,
            'subscription.status': subStatus,
            'subscription.hasUsedTrial': true,
            'subscription.startDate': user.subscription?.startDate || now,
            'subscription.nextBillingDate': newExpiry,
            'subscription.lastPaymentDate': now,
            'subscription.paymentMethod': method || 'UPI',
            'subscription.autoRenew': true,
            'subscription.lastAmountPaid': currentAmount,
            'subscription.planId': transaction.metadata?.productId || transaction.metadata?.offerId || matchedOffer?.rzpPlanId || matchedOffer?.id
        };

        if (transaction.orderId && (transaction.orderId.startsWith('sub_') || transaction.orderId.startsWith('S_'))) {
            updateFields['subscription.id'] = transaction.orderId;
        } else if (transaction.gateway === 'google_play') {
            updateFields['subscription.id'] = transaction.gatewayTransactionId || transaction.metadata?.purchaseToken;
            if (transaction.metadata?.orderId) {
                updateFields['subscription.googleOrderId'] = transaction.metadata.orderId;
            }
        }

        const newHistoryEntry = {
            orderId: transactionId,
            paymentId: transaction.gatewayTransactionId || transaction.paymentId,
            amount: currentAmount,
            status: 'SUCCESS',
            method: method || 'UPI',
            expiryDate: newExpiry,
            subscriptionStatus: subStatus,
            purchaseToken: transaction.metadata?.purchaseToken || transaction.gatewayTransactionId,
            productId: transaction.metadata?.productId || transaction.metadata?.offerId || matchedOffer?.googlePlayId || matchedOffer?.rzpPlanId,
            offerId: matchedOffer?.id || transaction.metadata?.offerId,
            timestamp: now
        };

        const updatedUser = await User.findOneAndUpdate(
            phoneQuery(normalizedPhone),
            {
                $set: updateFields,
                $push: { paymentHistory: newHistoryEntry }
            },
            { new: true }
        );

        // Update Cumulative Total
        const finalTotal = updatedUser.paymentHistory.filter(h => h.status === 'SUCCESS').reduce((sum, h) => sum + (h.amount || 0), 0);
        await User.updateOne(phoneQuery(normalizedPhone), { $set: { 'subscription.totalAmountPaid': finalTotal } });

        if (io) io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { isPremium: true, status: subStatus });
        return updatedUser;
    }

    static async syncWithProvider(phone, io) {
        try {
            const normalizedPhone = normalize(phone);
            let user = await User.findOne(phoneQuery(normalizedPhone));
            if (!user) throw new Error("User not found");

            const subId = user.subscription?.id;
            if (!subId) return { success: true, user, message: "No active subscription ID to sync." };

            const gateway = (user.subscription?.paymentMethod?.toLowerCase().includes('google') || subId.startsWith('GPA.')) ? 'google_play' : 'razorpay';
            const provider = await this.getProvider(gateway);

            let updatedData = {};

            if (gateway === 'razorpay') {
                if (subId.startsWith('sub_')) {
                    const subDetails = await provider.client.subscriptions.fetch(subId);
                    let status = 'expired';
                    if (['active', 'authenticated'].includes(subDetails.status)) status = 'active';
                    if (subDetails.status === 'cancelled') status = 'cancelled';

                    const nextBillTimestamp = subDetails.next_billing_at || subDetails.current_end || subDetails.start_at;
                    updatedData = {
                        status,
                        nextBillingDate: nextBillTimestamp ? new Date(nextBillTimestamp * 1000) : null,
                        autoRenew: !['cancelled', 'expired'].includes(subDetails.status)
                    };
                }
            } else if (gateway === 'google_play') {
                let purchaseToken = subId;
                let productId = user.subscription?.planId || 'gogo_monthly_199';

                if (purchaseToken.startsWith('GPA.')) {
                    const tx = await PaymentTransaction.findOne({ userPhone: normalizedPhone, gateway: 'google_play', status: 'SUCCESS' }).sort({ createdAt: -1 });
                    if (tx) purchaseToken = tx.gatewayTransactionId || tx.metadata?.purchaseToken;
                }

                if (purchaseToken && !purchaseToken.startsWith('GPA.')) {
                    const verification = await provider.verifyPayment({ purchaseToken, productId });
                    if (verification.success && verification.expiryTimeMillis) {
                        const expiry = parseInt(verification.expiryTimeMillis);
                        const googleOrderId = verification.orderId;

                        updatedData = {
                            status: (expiry > Date.now()) ? 'active' : 'expired',
                            nextBillingDate: new Date(expiry),
                            autoRenew: verification.autoRenewing || false,
                            paymentState: verification.raw?.paymentState,
                            orderId: googleOrderId
                        };

                        if (googleOrderId && googleOrderId.startsWith('GPA.')) {
                            // FRESH DATA FETCH FOR SYNC LOOP
                            user = await User.findById(user._id);

                            // AGGRESSIVE CLEANUP: Remove any temp GP_ entries for this user
                            await User.updateOne({ _id: user._id }, { $pull: { paymentHistory: { orderId: /^GP_/ } } });

                            const exactMatch = user.paymentHistory?.find(h => h.orderId === googleOrderId);
                            const isPending = (verification.raw?.paymentState === 0 || verification.raw?.paymentState === 3);

                            if (!exactMatch) {
                                let amount = verification.amount || 0;
                                if (!googleOrderId.includes('..')) {
                                    // Introductory Force: GPA... without dots is Trial
                                    amount = (verification.raw?.introductoryPriceInfo ? (parseInt(verification.raw.introductoryPriceInfo.introductoryPriceAmountMicros)/1000000) : 4);
                                } else if (amount === 0) {
                                    amount = 199;
                                }

                                if (isPending) {
                                    await User.updateOne({ _id: user._id }, {
                                        $push: {
                                            paymentHistory: {
                                                orderId: googleOrderId, status: 'PENDING', amount: amount,
                                                method: 'Google Play', purchaseToken, productId, timestamp: new Date()
                                            }
                                        }
                                    });
                                } else {
                                    await this._updateUserSubscription(normalizedPhone, { orderId: googleOrderId, gateway: 'google_play', amount, gatewayTransactionId: purchaseToken, metadata: verification.raw, current_period_end: Math.floor(expiry / 1000) }, 'Google Play', io);
                                }
                            } else {
                                // If exists, FORCE UPDATE its properties to match Google Truth
                                let forceAmount = verification.amount || exactMatch.amount;
                                if (!googleOrderId.includes('..')) forceAmount = (verification.raw?.introductoryPriceInfo ? (parseInt(verification.raw.introductoryPriceInfo.introductoryPriceAmountMicros)/1000000) : 4);

                                if (!isPending) {
                                    await this._updateUserSubscription(normalizedPhone, { orderId: googleOrderId, gateway: 'google_play', amount: forceAmount, gatewayTransactionId: purchaseToken, metadata: verification.raw, current_period_end: Math.floor(expiry / 1000) }, 'Google Play', io);
                                } else {
                                    // Ensure it stays PENDING if Google says so
                                    await User.updateOne({ _id: user._id, "paymentHistory.orderId": googleOrderId }, { $set: { "paymentHistory.$.status": 'PENDING', "paymentHistory.$.amount": forceAmount } });
                                }
                            }
                        }
                    }
                }
            }

            if (Object.keys(updatedData).length > 0) {
                const now = new Date();
                const existingExpiry = user.premiumExpiry;
                const providerExpiry = updatedData.nextBillingDate;
                const effectiveExpiry = gateway === 'razorpay' && existingExpiry && (!providerExpiry || existingExpiry > providerExpiry)
                    ? existingExpiry
                    : providerExpiry;
                const isPremium = updatedData.status === 'active' || (effectiveExpiry && effectiveExpiry > now);
                const updatedUser = await User.findOneAndUpdate(
                    phoneQuery(normalizedPhone),
                    {
                        $set: {
                            isPremium, premiumExpiry: effectiveExpiry,
                            'subscription.status': updatedData.status, 'subscription.nextBillingDate': effectiveExpiry,
                            'subscription.autoRenew': updatedData.autoRenew, 'subscription.googlePaymentState': updatedData.paymentState,
                            'subscription.googleOrderId': updatedData.orderId
                        }
                    },
                    { new: true }
                );
                return { success: true, user: updatedUser };
            }
            return { success: true, user: await User.findOne(phoneQuery(normalizedPhone)) };
        } catch (error) {
            console.error(`📡 Provider Sync Error (${phone}):`, error.message);
            return { success: false, message: error.message };
        }
    }

    static async revokeSubscription(phone, status = 'expired') {
        const normalizedPhone = normalize(phone);
        const updateFields = { 'subscription.status': status, 'subscription.autoRenew': false };
        if (status === 'expired') updateFields.isPremium = false;
        return await User.findOneAndUpdate(phoneQuery(normalizedPhone), { $set: updateFields }, { new: true });
    }

    static async syncUserStatus(phone) {
        const normalizedPhone = normalize(phone);
        const user = await User.findOne(phoneQuery(normalizedPhone));
        if (!user) return { isPremium: false, status: 'none' };

        const config = await Config.findOne({ key: 'payment_settings' });
        const settings = config?.value || {};
        const offerConfig = await Config.findOne({ key: 'special_offers' });
        const featuredOffer = offerConfig?.value?.offers?.[0];

        const now = new Date();
        let offerData = null;

        if (!user.isPremium) {
            if (!user.subscription?.hasUsedTrial && settings.trialPrice < 10) {
                offerData = { price: settings.trialPrice || 1, duration: settings.trialDuration || 1, title: "Special Trial Offer! 🎁", message: `Get full access for just ₹${settings.trialPrice}! Limited time trial.`, isTrial: true };
            } else if (featuredOffer) {
                offerData = { price: featuredOffer.price, planId: featuredOffer.id, title: featuredOffer.name || "Exclusive Offer! ✨", message: `Upgrade to Gold for just ₹${featuredOffer.price}. Limited time.`, isTrial: false, duration: featuredOffer.duration };
            }
        }

        if (user.isPremium && user.premiumExpiry && user.premiumExpiry < now) {
            user.isPremium = false;
            user.subscription.status = 'expired';
            await user.save();
        }

        return { isPremium: user.isPremium, status: user.subscription?.status || 'none', expiry: user.premiumExpiry, premiumPlan: user.premiumPlan, subscription: user.subscription, paymentHistory: (user.paymentHistory || []).slice(-10), offer: offerData };
    }

    static async cancelSubscription(phone) {
        const normalizedPhone = normalize(phone);
        const user = await User.findOne(phoneQuery(normalizedPhone));
        if (!user || !user.subscription?.id) throw new Error("No active subscription found");

        const provider = await this.getProvider('razorpay');
        try {
            const subDetails = await provider.client.subscriptions.fetch(user.subscription.id);
            if (subDetails.status === 'cancelled') {
                user.subscription.status = 'cancelled';
                user.subscription.autoRenew = false;
                await user.save();
                return { success: true, message: "Subscription was already cancelled." };
            }
            const cancelImmediately = (subDetails.status === 'authenticated' || subDetails.status === 'created' || (subDetails.paid_count === 0));
            try {
                await provider.client.subscriptions.cancel(user.subscription.id, !cancelImmediately);
            } catch (innerErr) {
                const innerDesc = (innerErr.error?.description || innerErr.description || "").toLowerCase();
                if (!(innerDesc.includes('not cancellable') || innerDesc.includes('already cancelled') || innerDesc.includes('no billing cycle'))) throw innerErr;
            }
            user.subscription.status = 'cancelled';
            user.subscription.autoRenew = false;
            await user.save();
            return { success: true, message: "Subscription successfully cancelled." };
        } catch (err) {
            const errorDesc = (err.error?.description || err.description || err.message || "").toLowerCase();
            if (errorDesc.includes('not cancellable') || errorDesc.includes('already cancelled') || errorDesc.includes('no billing cycle') || errorDesc.includes('cancelled status')) {
                 if (user) { user.subscription.status = 'cancelled'; user.subscription.autoRenew = false; await user.save(); }
                 return { success: true, message: "Subscription auto-pay disabled." };
            }
            throw new Error(err.message || "Failed to cancel subscription");
        }
    }

    static async verifyPayment(phone, paymentData, io) {
        try {
            const normalizedPhone = normalize(phone);
            const gateway = paymentData.gateway || 'razorpay';
            const provider = await this.getProvider(gateway);

            const verification = await provider.verifyPayment(paymentData);
            if (verification.success) {
                let transaction;
                const orderId = paymentData.orderId || paymentData.razorpay_subscription_id || paymentData.merchantTransactionId || verification.transactionId;
                const isPending = gateway === 'google_play' && (verification.raw?.paymentState === 0 || verification.raw?.paymentState === 3);
                const finalStatus = isPending ? 'PENDING' : 'SUCCESS';

                let currentPeriodEnd = null;
                if (gateway === 'razorpay' && (paymentData.razorpay_subscription_id || orderId.startsWith('sub_'))) {
                    try {
                        const subId = paymentData.razorpay_subscription_id || orderId;
                        const subDetails = await provider.client.subscriptions.fetch(subId);
                        if (subDetails) currentPeriodEnd = subDetails.next_billing_at || subDetails.current_end || subDetails.start_at;
                    } catch (err) { console.error("Error fetching sub details:", err); }
                }

                if (gateway === 'google_play' && verification.expiryTimeMillis) currentPeriodEnd = Math.floor(verification.expiryTimeMillis / 1000);

                const existingTransaction = await PaymentTransaction.findOne({ orderId, status: 'PENDING' });
                if (existingTransaction) {
                    transaction = await PaymentTransaction.findOneAndUpdate(
                        { _id: existingTransaction._id },
                        {
                            orderId: verification.orderId || orderId,
                            status: finalStatus, gatewayTransactionId: verification.transactionId,
                            paymentMethod: paymentData.method || (gateway === 'google_play' ? 'Google Play' : 'UPI'),
                            current_period_end: currentPeriodEnd,
                            metadata: {
                                ...existingTransaction.metadata,
                                ...verification.raw,
                                productId: paymentData.productId || existingTransaction.metadata?.productId,
                                googlePlayId: paymentData.googlePlayId || existingTransaction.metadata?.googlePlayId,
                                googlePlaySubId: paymentData.googlePlaySubId || existingTransaction.metadata?.googlePlaySubId,
                                temporaryOrderId: existingTransaction.orderId
                            }
                        },
                        { new: true }
                    );
                }

                if (!transaction && gateway === 'google_play') {
                    let amount = verification.amount || paymentData.amount || 0;
                    transaction = await PaymentTransaction.create({
                        orderId: verification.orderId || orderId,
                        userPhone: normalizedPhone, gateway: 'google_play',
                        amount, status: finalStatus, gatewayTransactionId: verification.transactionId,
                        paymentMethod: 'Google Play', current_period_end: currentPeriodEnd,
                        metadata: {
                            ...verification.raw,
                            productId: paymentData.productId,
                            googlePlayId: paymentData.googlePlayId,
                            googlePlaySubId: paymentData.googlePlaySubId,
                            temporaryOrderId: (orderId && orderId.startsWith('gp_')) ? orderId : null
                        }
                    });
                }

                if (!transaction) {
                    const alreadyDone = await PaymentTransaction.findOne({ orderId, status: 'SUCCESS' });
                    if (alreadyDone) return { success: true, user: await User.findOne(phoneQuery(normalizedPhone)) };
                    throw new Error("Invalid or duplicate transaction");
                }

                if (finalStatus === 'SUCCESS') {
                    const updatedUser = await this._updateUserSubscription(normalizedPhone, transaction, transaction.paymentMethod, io);
                    return { success: true, user: updatedUser };
                } else {
                    return { success: true, user: await User.findOne(phoneQuery(normalizedPhone)), message: "Payment is pending validation." };
                }
            }
            return { success: false, message: "Verification failed" };
        } catch (e) { return { success: false, message: e.message }; }
    }

    static async processWebhook(gateway, payload, signature, rawBody, io) {
        try {
            const provider = await this.getProvider(gateway);
            const result = await provider.handleWebhook(payload, signature, rawBody);
            if (result.status === 'IGNORE') return { success: true };

            let phone = result.userPhone;
            let transaction = null;

            if (gateway === 'google_play' && result.purchaseToken) {
                const existingTx = await PaymentTransaction.findOne({ $or: [{ orderId: result.purchaseToken }, { gatewayTransactionId: result.purchaseToken }] });
                if (existingTx) { phone = existingTx.userPhone; transaction = existingTx; }
                else {
                    const userWithToken = await User.findOne({ $or: [{ 'subscription.id': result.purchaseToken }, { 'paymentHistory.orderId': result.purchaseToken }] });
                    if (userWithToken) phone = userWithToken.phone;
                }
            }

            if (!phone || phone === 'UNKNOWN') return { success: true };
            const normalizedPhone = normalize(phone);
            const orderId = result.orderId || (gateway === 'google_play' ? result.purchaseToken : null);

            if (!transaction && orderId) transaction = await PaymentTransaction.findOne({ orderId: orderId });

            if (!transaction) {
                let amount = result.amount || 0;
                if (gateway === 'google_play' && amount === 0) {
                    try {
                        const offerConfig = await Config.findOne({ key: 'special_offers' });
                        const productId = result.productId || (await User.findOne(phoneQuery(normalizedPhone)))?.subscription?.planId;
                        const matchedOffer = offerConfig?.value?.offers?.find(o => o.googlePlayId === productId || o.googlePlaySubId === productId);
                        amount = matchedOffer ? matchedOffer.price : 199;
                    } catch (err) {}
                }
                transaction = await PaymentTransaction.create({
                    orderId: orderId || `wh_${Date.now()}`, userPhone: normalizedPhone, gateway,
                    amount, status: 'SUCCESS', gatewayTransactionId: result.paymentId || result.purchaseToken,
                    current_period_end: result.next_billing_at || result.current_period_end || result.start_at,
                    metadata: { productId: result.productId }
                });
            } else {
                transaction.status = 'SUCCESS';
                if (result.paymentId) transaction.gatewayTransactionId = result.paymentId;
                const bestDate = result.next_billing_at || result.current_period_end || result.start_at;
                if (bestDate) transaction.current_period_end = bestDate;
                await transaction.save();
            }

            if (gateway === 'google_play') {
                const syncResult = await this.syncWithProvider(normalizedPhone, io).catch(e => {});
                if (syncResult?.success && syncResult.user?.isPremium && io) {
                    io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { isPremium: true, status: syncResult.user.subscription?.status || 'active', message: "Subscription Renewed 🚀" });
                }
            } else {
                switch (result.status) {
                    case 'SUCCESS': case 'RENEWAL_SUCCESS': case 'TRIAL_SUCCESS':
                        await this._updateUserSubscription(normalizedPhone, {
                            ...result,
                            orderId: transaction.orderId || result.orderId,
                            amount: transaction.amount || result.amount,
                            gatewayTransactionId: transaction.gatewayTransactionId || result.paymentId,
                            current_period_end: transaction.current_period_end || result.current_period_end || result.next_billing_at || result.start_at,
                            metadata: {
                                ...(transaction.metadata || {}),
                                webhookEvent: result.event
                            }
                        }, transaction.paymentMethod || 'UPI', io); break;
                    case 'CANCELLED':
                        await User.updateOne(phoneQuery(normalizedPhone), { $set: { 'subscription.autoRenew': false, 'subscription.status': 'cancelled' } });
                        if (io) io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { status: 'cancelled', message: "Auto-pay disabled", type: 'warning' });
                        break;
                    case 'EXPIRED':
                        await this.revokeSubscription(normalizedPhone, 'expired');
                        if (io) io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { isPremium: false, status: 'expired', message: "Membership Expired", type: 'warning' });
                        break;
                    case 'PAYMENT_FAILED':
                        if (orderId) await User.updateOne({ ...phoneQuery(normalizedPhone), "paymentHistory.orderId": orderId }, { $set: { "paymentHistory.$.status": 'FAILED' } }).catch(() => {});
                        if (io) io.to(`user_${normalizedPhone}`).emit('premium_status_refresh', { status: 'payment_failed', message: "Payment Failed ⚠️", type: 'error' });
                        break;
                }
            }
            return { success: true };
        } catch (e) { console.error("Webhook Processing Error:", e.message); return { success: false }; }
    }
}

module.exports = PaymentService;
