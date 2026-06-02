async function loadMonetization() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Financial Operations & Monetization";

    // Skeleton Loading State
    mainContent.innerHTML = `
        <div class="space-y-10 animate-fade pb-20">
            <div class="grid grid-cols-4 gap-6">
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
            </div>
            <div class="grid grid-cols-4 gap-6">
                ${Array(4).fill('<div class="glass p-6 rounded-3xl skeleton h-20"></div>').join('')}
            </div>
            <div class="grid grid-cols-2 gap-10">
                <div class="skeleton h-[30rem] rounded-[3rem]"></div>
                <div class="skeleton h-[30rem] rounded-[3rem]"></div>
            </div>
        </div>
    `;

    try {
        const [configData, gpConfigData, reviewData, statsData] = await Promise.all([
            API.getConfig('payment_settings').catch(e => ({ success: false, config: {} })),
            API.getConfig('google_play_settings').catch(e => ({ success: false, config: {} })),
            API.getConfig('review_mode_config').catch(e => ({ success: false, config: { isReviewMode: false } })),
            API.getMonetizationStats().catch(e => ({ success: false, stats: {} }))
        ]);

        let settings = configData.config || {};
        let gpSettings = gpConfigData.config || {};
        let isReviewMode = reviewData.config?.isReviewMode || false;

        if (!settings.activeGateway) settings.activeGateway = 'razorpay';

        let s = statsData.stats || {};
        const stats = {
            grossRevenue: s.grossRevenue || 0,
            todayEarnings: s.todayEarnings || 0,
            monthlyRevenue: s.monthlyRevenue || 0,
            activePremiumUsers: s.activePremiumUsers || 0,
            topGateway: s.topGateway || 'N/A',
            arpu: s.arpu || 0,
            failedToday: s.failedToday || 0,
            subscriptionHealth: s.subscriptionHealth || { churnRate: '0.0%' }
        };

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade pb-20">
                <!-- Google Compliance Switch -->
                <div class="glass p-6 rounded-[2rem] border border-red-500/20 flex items-center justify-between">
                    <div class="flex items-center space-x-4">
                        <div class="p-3 bg-red-500/10 rounded-2xl">
                            <i class="fas fa-shield-check text-red-500 text-lg"></i>
                        </div>
                        <div>
                            <h3 class="text-xs font-black text-white uppercase tracking-wider">Google Compliance Switch</h3>
                            <p id="reviewModeStatus" class="text-[9px] font-bold mt-0.5 ${isReviewMode ? 'text-emerald-500' : 'text-slate-500'}">
                                ${isReviewMode ? 'Review Mode Active (Payments Hidden)' : 'Live Mode Active (Payments Visible)'}
                            </p>
                        </div>
                    </div>
                    <label class="relative inline-flex items-center cursor-pointer scale-110 mr-4">
                        <input type="checkbox" id="review_mode_toggle" ${isReviewMode ? 'checked' : ''} onchange="toggleReviewMode(this)" class="sr-only peer">
                        <div class="w-14 h-7 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all peer-checked:bg-red-500"></div>
                    </label>
                </div>

                <!-- Primary Revenue Cards -->
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Gross Revenue', '₹' + stats.grossRevenue.toLocaleString(), 'Lifetime Earnings', 'text-emerald-500', 'gross-revenue')}
                    ${UI.card('Today Earnings', '₹' + stats.todayEarnings.toLocaleString(), '24h Performance', 'text-orange-500', 'today-earnings')}
                    ${UI.card('Monthly Revenue', '₹' + stats.monthlyRevenue.toLocaleString(), 'Current Period', 'text-blue-500', 'monthly-revenue')}
                    ${UI.card('Active Premium', stats.activePremiumUsers.toLocaleString(), 'Live Subscriptions', 'text-pink-500', 'active-premium')}
                </div>

                <div class="grid grid-cols-2 gap-10">
                    <!-- Pricing & Gateway Config -->
                    <div class="space-y-6">

                        <!-- NEW PRICING ENGINE -->
                        <div class="glass p-10 rounded-[3rem] space-y-8 border border-emerald-500/10">
                            <div class="border-b border-white/5 pb-6">
                                <h3 class="text-xs font-black text-white uppercase tracking-widest">Subscription Pricing Engine</h3>
                                <p class="text-[8px] text-slate-500 mt-1 uppercase font-bold">Control upfront and display costs</p>
                            </div>

                            <div class="grid grid-cols-2 gap-6">
                                <div>
                                    <label class="text-[9px] font-black text-emerald-500 uppercase tracking-widest ml-1">Trial Price (INR)</label>
                                    <input type="number" id="trialPrice" value="${settings.trialPrice || 1}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-emerald-500 font-bold mt-2 focus:border-emerald-500/50 transition">
                                    <p class="text-[7px] text-slate-500 mt-2 uppercase italic">Instant Setup/Trial Fee</p>
                                </div>
                                <div>
                                    <label class="text-[9px] font-black text-orange-500 uppercase tracking-widest ml-1">Main Price (INR)</label>
                                    <input type="number" id="monthlyPrice" value="${settings.monthlyPrice || 199}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-white font-bold mt-2 focus:border-orange-500/50 transition">
                                    <p class="text-[7px] text-slate-500 mt-2 uppercase italic">Display Price on App</p>
                                </div>
                            </div>

                            <button onclick="savePricingStrategy()" class="w-full py-4 bg-emerald-500 text-black rounded-2xl text-[10px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-emerald-500/30">
                                <i class="fas fa-save mr-2"></i> Save Pricing Strategy
                            </button>

                            <!-- Retention Win-back Offer -->
                            <div class="mt-8 pt-8 border-t border-white/5 space-y-6">
                                <div class="flex justify-between items-center">
                                    <h4 class="text-[10px] font-black text-pink-500 uppercase tracking-widest">Retention Campaign</h4>
                                    <label class="relative inline-flex items-center cursor-pointer">
                                        <input type="checkbox" id="offer_toggle" ${settings.isOfferEnabled ? 'checked' : ''} class="sr-only peer">
                                        <div class="w-10 h-5 bg-white/10 rounded-full peer peer-checked:bg-pink-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-5"></div>
                                    </label>
                                </div>
                                <div class="grid grid-cols-2 gap-4">
                                    <input type="number" id="offerPrice" value="${settings.offerPrice || 99}" placeholder="Offer Price" class="bg-black/20 border border-white/5 p-3 rounded-xl text-xs text-white">
                                    <input type="text" id="offerPlanId" value="${settings.offerPlanId || ''}" placeholder="Offer Plan ID" class="bg-black/20 border border-white/5 p-3 rounded-xl text-[10px] text-white">
                                    <div class="col-span-2 grid grid-cols-2 gap-4">
                                        <div>
                                            <p class="text-[7px] text-slate-500 mb-1">SHOW AFTER (DAYS)</p>
                                            <input type="number" id="offerStartDay" value="${settings.offerStartDay || 1}" class="w-full bg-black/20 border border-white/5 p-2 rounded-lg text-xs text-white">
                                        </div>
                                        <div>
                                            <p class="text-[7px] text-slate-500 mb-1">HIDE AFTER (DAYS)</p>
                                            <input type="number" id="offerEndDay" value="${settings.offerEndDay || 7}" class="w-full bg-black/20 border border-white/5 p-2 rounded-lg text-xs text-white">
                                        </div>
                                    </div>
                                </div>
                                <button onclick="saveOfferStrategy()" class="w-full py-3 bg-pink-500/10 text-pink-500 border border-pink-500/20 rounded-xl text-[9px] font-black uppercase hover:bg-pink-500 hover:text-white transition">Update Win-back Offer</button>
                            </div>
                        </div>

                        <!-- GATEWAY CONFIG -->
                        <div class="glass p-10 rounded-[3rem] space-y-8 border border-white/5">
                            <div class="border-b border-white/5 pb-6">
                                <h3 class="text-xs font-black text-white uppercase tracking-widest">Gateway Credentials</h3>
                            </div>

                            <div class="flex items-center justify-between glass p-4 rounded-2xl">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase">Enable UPI Payments</p>
                                </div>
                                <label class="relative inline-flex items-center cursor-pointer">
                                    <input type="checkbox" id="upi_toggle" ${settings.isUpiEnabled !== false ? 'checked' : ''} class="sr-only peer">
                                    <div class="w-11 h-6 bg-white/10 rounded-full peer peer-checked:bg-emerald-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:after:translate-x-5"></div>
                                </label>
                            </div>

                            <div class="flex gap-2">
                                ${['razorpay', 'phonepe', 'cashfree'].map(g => `
                                    <button onclick="toggleGateway('${g}')" class="flex-1 py-3 rounded-xl border ${settings.activeGateway === g ? 'border-orange-500 bg-orange-500/10 text-orange-500' : 'border-white/5 bg-white/5 text-slate-500'} transition text-[10px] font-black uppercase">
                                        ${g}
                                    </button>
                                `).join('')}
                            </div>

                            <div id="activeGatewayForm">
                                ${renderGatewayForm(settings.activeGateway, settings)}
                            </div>

                            <button onclick="savePaymentSettings('${settings.activeGateway}')" class="w-full py-4 bg-white/5 text-white border border-white/10 rounded-xl text-[10px] font-black uppercase hover:bg-white/10 transition">
                                Sync Gateway Keys
                            </button>
                        </div>
                    </div>

                    <!-- Live Activity Feed -->
                    <div class="glass p-10 rounded-[3rem] flex flex-col">
                        <div class="border-b border-white/5 pb-6 mb-6">
                            <h3 class="text-xs font-black text-white uppercase tracking-widest">Realtime Financial Intelligence</h3>
                        </div>
                        <div id="financeActivity" class="flex-1 space-y-4 overflow-y-auto h-[40rem] pr-2 font-mono text-[10px]">
                            <div class="text-slate-500 opacity-50 uppercase italic text-center py-20">Monitoring live stream...</div>
                        </div>
                    </div>
                </div>

                <!-- Payment History -->
                <div class="glass rounded-[3rem] overflow-hidden">
                    <div class="p-8 border-b border-white/5 flex justify-between items-center bg-white/5">
                        <h3 class="text-xs font-black text-white uppercase">Ledger History</h3>
                        <div class="flex items-center space-x-4">
                            <input type="text" id="historySearch" placeholder="Phone / Order ID" class="bg-black/20 border border-white/5 px-4 py-2 rounded-xl text-[10px] outline-none w-64">
                            <button onclick="searchHistory()" class="px-4 py-2 bg-white/5 rounded-xl text-[10px] font-bold uppercase hover:bg-white/10">Filter</button>
                        </div>
                    </div>
                    <div id="historyTable">
                        ${UI.skeletonTable(5)}
                    </div>
                </div>
            </div>
        `;

        loadPaymentHistory();
    } catch (err) {
        console.error(err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 font-black uppercase">Monetization Sync Failed</p>`;
    }
}

function renderGatewayForm(active, settings) {
    if (active === 'razorpay') {
        const r = settings.razorpay || {};
        return `
            <div class="flex flex-col space-y-6 pt-4">
                <div class="bg-black/40 p-5 rounded-2xl border border-white/5">
                    <label class="text-[9px] font-black text-orange-500 uppercase tracking-widest ml-1">Razorpay Plan ID (₹199)</label>
                    <input type="text" id="rp_plan_id" value="${r.planId || ''}" placeholder="plan_xxx" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-white mt-2">
                </div>
                <div class="grid grid-cols-2 gap-4">
                    <input type="text" id="rp_key_id" value="${r.keyId || ''}" placeholder="Key ID" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white">
                    <input type="password" id="rp_key_secret" value="${r.keySecret || ''}" placeholder="Key Secret" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white">
                </div>
                <input type="password" id="rp_webhook_secret" value="${r.webhookSecret || ''}" placeholder="Webhook Secret" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white">
            </div>
        `;
    }
    return `<p class="text-xs text-slate-500 text-center py-10 uppercase font-bold italic opacity-30">${active} details detail soon</p>`;
}

async function savePricingStrategy() {
    try {
        const trialVal = document.getElementById('trialPrice').value;
        const monthlyVal = document.getElementById('monthlyPrice').value;

        const data = await API.getConfig('payment_settings');
        const settings = data.config || {};

        settings.trialPrice = parseInt(trialVal) || 1;
        settings.monthlyPrice = parseInt(monthlyVal) || 199;

        await API.updateConfig('payment_settings', settings);

        // BROADCAST CHANGE TO ALL USERS
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});

        showSystemToast("Pricing Saved", "Strategy updated & Broadcasted", 'bg-emerald-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "API communication error", 'bg-red-500');
    }
}

async function saveOfferStrategy() {
    try {
        const data = await API.getConfig('payment_settings');
        const settings = data.config || {};

        settings.isOfferEnabled = document.getElementById('offer_toggle').checked;
        settings.offerPrice = parseInt(document.getElementById('offerPrice').value) || 99;
        settings.offerPlanId = document.getElementById('offerPlanId').value;
        settings.offerStartDay = parseInt(document.getElementById('offerStartDay').value) || 1;
        settings.offerEndDay = parseInt(document.getElementById('offerEndDay').value) || 7;

        await API.updateConfig('payment_settings', settings);

        // BROADCAST CHANGE TO ALL USERS
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});

        showSystemToast("Offer Updated", "Campaign active & Broadcasted", 'bg-pink-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "Campaign update failed", 'bg-red-500');
    }
}

async function savePaymentSettings(activeGateway) {
    try {
        const data = await API.getConfig('payment_settings');
        const settings = data.config || { activeGateway: 'razorpay' };

        settings.isUpiEnabled = document.getElementById('upi_toggle').checked;

        if (activeGateway === 'razorpay') {
            settings.razorpay = {
                keyId: document.getElementById('rp_key_id').value,
                keySecret: document.getElementById('rp_key_secret').value,
                planId: document.getElementById('rp_plan_id').value,
                webhookSecret: document.getElementById('rp_webhook_secret').value
            };
        }
        settings.activeGateway = activeGateway;
        await API.updateConfig('payment_settings', settings);
        showSystemToast("Gateway Updated", "API credentials synced", 'bg-emerald-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Sync Failed", "Credential save failed", 'bg-red-500');
    }
}

async function toggleReviewMode(el) {
    try {
        // Only call updateConfig. It already handles the broadcast in AdminController.js
        await API.updateConfig('review_mode_config', { isReviewMode: el.checked });

        showSystemToast("Compliance Changed", `Mode: ${el.checked ? 'REVIEW' : 'LIVE'}`, el.checked ? 'bg-red-500' : 'bg-emerald-500');
        loadMonetization();
    } catch (e) {
        el.checked = !el.checked;
        showSystemToast("Sync Error", "Server not responding", 'bg-red-500');
    }
}

async function toggleGateway(g) {
    try {
        const data = await API.getConfig('payment_settings');
        const settings = data.config || {};
        settings.activeGateway = g;
        await API.updateConfig('payment_settings', settings);
        showSystemToast("Gateway Switched", `Active: ${g.toUpperCase()}`, 'bg-orange-500');
        loadMonetization();
    } catch (e) { }
}

async function loadPaymentHistory(page = 1, search = '') {
    const container = document.getElementById('historyTable');
    try {
        const data = await API.getPaymentHistory(page);
        const filtered = search ? data.transactions.filter(t => t.userPhone.includes(search) || t.orderId.includes(search)) : data.transactions;
        const rows = filtered.map(t => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6">
                    <p class="text-white text-xs font-bold">${t.userPhone}</p>
                    <p class="text-[8px] text-slate-500 uppercase">${t.orderId}</p>
                </td>
                <td class="p-6 text-xs font-black text-white">₹${t.amount}</td>
                <td class="p-6">${UI.badge(t.status, t.status === 'SUCCESS' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}</td>
                <td class="p-6 text-[10px] text-slate-500 font-bold uppercase">${t.gateway}</td>
                <td class="p-6 text-[9px] text-slate-400 font-medium">${new Date(t.createdAt).toLocaleString()}</td>
            </tr>
        `);
        container.innerHTML = UI.table(['Customer', 'Amount', 'Status', 'Gateway', 'Timestamp'], rows);
    } catch (e) { }
}

async function searchHistory() {
    loadPaymentHistory(1, document.getElementById('historySearch').value);
}
