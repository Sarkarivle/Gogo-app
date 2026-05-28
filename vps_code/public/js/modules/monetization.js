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

        // Ensure activeGateway is set to razorpay by default if missing
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

                <!-- Secondary Financial Metrics -->
                <div class="grid grid-cols-4 gap-6">
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Top Gateway</p>
                        <p class="text-xl font-black text-white uppercase mt-1">${stats.topGateway}</p>
                    </div>
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Avg ARPU</p>
                        <p class="text-xl font-black text-white mt-1">₹${stats.arpu}</p>
                    </div>
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Failed Today</p>
                        <p class="text-xl font-black text-red-500 mt-1">${stats.failedToday}</p>
                    </div>
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Churn Rate</p>
                        <p class="text-xl font-black text-white mt-1">${stats.subscriptionHealth.churnRate}</p>
                    </div>
                </div>

                <div class="grid grid-cols-2 gap-10">
                    <!-- Gateway Config -->
                    <div class="space-y-6">
                        <div class="glass p-10 rounded-[3rem] space-y-8 border border-orange-500/10">
                            <div class="border-b border-white/5 pb-6">
                                <h3 class="text-xs font-black text-white uppercase">UPI Gateways (Local Banks)</h3>
                                <p class="text-[8px] text-slate-500 mt-1 uppercase font-bold">Configure Razorpay, PhonePe or Cashfree</p>
                            </div>

                            <div class="flex items-center justify-between glass p-4 rounded-2xl">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase">Enable UPI Payments</p>
                                    <p class="text-[8px] text-slate-500 uppercase">Visible on checkout page</p>
                                </div>
                                <label class="relative inline-flex items-center cursor-pointer">
                                    <input type="checkbox" id="upi_toggle" ${settings.isUpiEnabled !== false ? 'checked' : ''} class="sr-only peer">
                                    <div class="w-11 h-6 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-emerald-500"></div>
                                </label>
                            </div>

                            <div class="flex gap-2">
                                ${['razorpay', 'phonepe', 'cashfree'].map(g => `
                                    <button onclick="toggleGateway('${g}')" class="flex-1 py-3 rounded-xl border ${settings.activeGateway === g ? 'border-orange-500 bg-orange-500/10 text-orange-500' : 'border-white/5 bg-white/5 text-slate-500'} transition text-[10px] font-black uppercase">
                                        ${g}
                                    </button>
                                `).join('')}
                            </div>

                            <div id="activeGatewayForm" class="space-y-6 pt-4">
                                ${renderGatewayForm(settings.activeGateway, settings)}
                            </div>

                            <button onclick="savePaymentSettings('${settings.activeGateway}')" class="w-full py-4 bg-orange-500 text-black rounded-xl text-[10px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-orange-500/20">
                                Sync UPI Config
                            </button>
                        </div>

                        <!-- Google Play Section -->
                        <div class="glass p-10 rounded-[3rem] space-y-8 border border-blue-500/10">
                            <div class="border-b border-white/5 pb-6">
                                <h3 class="text-xs font-black text-white uppercase">Google Play Billing</h3>
                                <p class="text-[8px] text-slate-500 mt-1 uppercase font-bold">Separate from UPI - Official Play Store Payment</p>
                            </div>

                            <div class="flex items-center justify-between glass p-4 rounded-2xl">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase">Enable Google Play</p>
                                    <p class="text-[8px] text-slate-500 uppercase">Direct Play Store Purchase</p>
                                </div>
                                <label class="relative inline-flex items-center cursor-pointer">
                                    <input type="checkbox" id="google_play_toggle" ${gpSettings.isEnabled === true ? 'checked' : ''} class="sr-only peer">
                                    <div class="w-11 h-6 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-500"></div>
                                </label>
                            </div>

                            <div id="googlePlayForm" class="space-y-6">
                                ${renderGatewayForm('google_play', { google_play: gpSettings })}
                            </div>

                            <button onclick="saveGooglePlaySettings()" class="w-full py-4 bg-blue-600 text-white rounded-xl text-[10px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-blue-500/20">
                                Sync Google Play Config
                            </button>
                        </div>
                    </div>

                    <!-- Live Activity Feed -->
                    <div class="glass p-10 rounded-[3rem] flex flex-col">
                        <div class="border-b border-white/5 pb-6 mb-6">
                            <h3 class="text-xs font-black text-white uppercase tracking-widest">Realtime Finance Feed</h3>
                        </div>
                        <div id="financeActivity" class="flex-1 space-y-4 overflow-y-auto h-96 pr-2 font-mono text-[10px]">
                            <div class="text-slate-500 opacity-50 uppercase italic text-center py-20">Waiting for live transactions...</div>
                        </div>
                    </div>
                </div>

                <!-- Payment History -->
                <div class="glass rounded-[3rem] overflow-hidden">
                    <div class="p-8 border-b border-white/5 flex justify-between items-center bg-white/5">
                        <h3 class="text-xs font-black text-white uppercase">Transaction History</h3>
                        <div class="flex items-center space-x-4">
                            <input type="text" id="historySearch" placeholder="Search by Phone / Order ID" class="bg-black/20 border border-white/5 px-4 py-2 rounded-xl text-[10px] outline-none focus:border-orange-500/50 w-64">
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
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[8px] font-bold text-slate-500 uppercase ml-1">Key ID</label>
                    <input type="text" id="rp_key_id" value="${r.keyId || ''}" placeholder="rzp_live_..." class="w-full bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white mt-1">
                </div>
                <div>
                    <label class="text-[8px] font-bold text-slate-500 uppercase ml-1">Key Secret</label>
                    <input type="password" id="rp_key_secret" value="${r.keySecret || ''}" placeholder="••••••••" class="w-full bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white mt-1">
                </div>
                <div>
                    <label class="text-[8px] font-bold text-slate-500 uppercase ml-1">Plan ID</label>
                    <input type="text" id="rp_plan_id" value="${r.planId || ''}" placeholder="plan_..." class="w-full bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white mt-1">
                </div>
                <div>
                    <label class="text-[8px] font-bold text-slate-500 uppercase ml-1">Webhook Secret</label>
                    <input type="password" id="rp_webhook_secret" value="${r.webhookSecret || ''}" placeholder="••••••••" class="w-full bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white mt-1">
                </div>
            </div>
        `;
    }
    if (active === 'phonepe') {
        const p = settings.phonepe || {};
        return `
            <div class="grid grid-cols-2 gap-4">
                <input type="text" id="pp_merchant_id" value="${p.merchantId || ''}" placeholder="Merchant ID" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <input type="password" id="pp_salt_key" value="${p.saltKey || ''}" placeholder="Salt Key" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <input type="text" id="pp_salt_index" value="${p.saltIndex || '1'}" placeholder="Salt Index" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <input type="password" id="pp_webhook_secret" value="${p.webhookSecret || ''}" placeholder="Webhook Secret" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <select id="pp_env" class="bg-[#12151f] border border-white/5 p-3 rounded-xl outline-none text-xs text-white col-span-2">
                    <option value="UAT" ${p.env === 'UAT' ? 'selected' : ''}>UAT (Testing)</option>
                    <option value="PROD" ${p.env === 'PROD' ? 'selected' : ''}>PROD (Production)</option>
                </select>
            </div>
        `;
    }
    if (active === 'cashfree') {
        const c = settings.cashfree || {};
        return `
            <div class="grid grid-cols-1 gap-4">
                <input type="text" id="cf_app_id" value="${c.appId || ''}" placeholder="App ID" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <input type="password" id="cf_secret_key" value="${c.secretKey || ''}" placeholder="Secret Key" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <select id="cf_env" class="bg-[#12151f] border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                    <option value="SANDBOX" ${c.env === 'SANDBOX' ? 'selected' : ''}>SANDBOX</option>
                    <option value="PROD" ${c.env === 'PROD' ? 'selected' : ''}>PROD</option>
                </select>
            </div>
        `;
    }
    if (active === 'google_play') {
        const g = settings.google_play || {};
        return `
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[8px] font-bold text-slate-500 uppercase ml-1">Monthly Plan Product ID</label>
                    <input type="text" id="gp_product_id" value="${g.productId || 'premium_gold_monthly'}" placeholder="premium_gold_monthly" class="w-full bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white mt-1">
                </div>
                <div>
                    <label class="text-[8px] font-bold text-slate-500 uppercase ml-1">Trial Plan Product ID</label>
                    <input type="text" id="gp_trial_product_id" value="${g.trialProductId || 'premium_gold_trial'}" placeholder="premium_gold_trial" class="w-full bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white mt-1">
                </div>
                <div class="col-span-2">
                    <label class="text-[8px] font-bold text-slate-500 uppercase ml-1">Service Account Key (JSON String)</label>
                    <textarea id="gp_service_account" placeholder="{ ... }" class="w-full bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-[10px] text-white mt-1 h-32">${g.serviceAccount ? JSON.stringify(g.serviceAccount) : ''}</textarea>
                </div>
            </div>
        `;
    }
    return `<p class="text-xs text-slate-500 text-center py-10 uppercase">Config not yet detailed for ${active}</p>`;
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
                <td class="p-6">
                    ${UI.badge(t.status, t.status === 'SUCCESS' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}
                </td>
                <td class="p-6 text-[10px] text-slate-500 font-bold uppercase">${t.gateway}</td>
                <td class="p-6 text-[9px] text-slate-400 font-medium">${new Date(t.createdAt).toLocaleString()}</td>
            </tr>
        `);

        container.innerHTML = UI.table(['Customer', 'Amount', 'Status', 'Gateway', 'Timestamp'], rows);
    } catch (e) {
        container.innerHTML = '<p class="p-10 text-center text-red-500 uppercase font-black">History Sync Failed</p>';
    }
}

function updateRevenueRealtime(data) {
    updateCardValue('gross-revenue', '₹' + data.grossRevenue.toLocaleString());
    updateCardValue('today-earnings', '₹' + data.todayEarnings.toLocaleString());
    updateCardValue('monthly-revenue', '₹' + data.monthlyRevenue.toLocaleString());
    updateCardValue('active-premium', data.activePremiumUsers.toLocaleString());

    // Secondary
    document.querySelectorAll('.glass .text-xl').forEach(el => {
        const labelEl = el.previousElementSibling;
        if (!labelEl) return;
        const label = labelEl.innerText;
        if (label === 'TOP GATEWAY') el.innerText = data.topGateway.toUpperCase();
        if (label === 'AVG ARPU') el.innerText = '₹' + data.arpu;
        if (label === 'FAILED TODAY') el.innerText = data.failedToday;
        if (label === 'CHURN RATE') el.innerText = data.subscriptionHealth?.churnRate || '0.0%';
    });
}

function appendFinanceActivity(data) {
    const feed = document.getElementById('financeActivity');
    if (!feed) return;

    if (feed.querySelector('.italic')) feed.innerHTML = '';

    const div = document.createElement('div');
    div.className = 'p-3 bg-white/5 rounded-xl border-l-2 border-emerald-500 animate-fade';
    div.innerHTML = `
        <div class="flex justify-between items-start">
            <div>
                <span class="text-emerald-500 font-black">${data.type.toUpperCase()}</span>
                <p class="text-white mt-1">User ${data.userPhone.replace(/(\d{3})\d{4}(\d{3})/, '$1****$2')} paid ₹${data.amount}</p>
                <p class="text-slate-500 text-[8px] mt-0.5">VIA ${data.gateway.toUpperCase()}</p>
            </div>
            <span class="opacity-30 text-[8px]">${new Date(data.timestamp).toLocaleTimeString()}</span>
        </div>
    `;
    feed.prepend(div);
    if (feed.children.length > 50) feed.lastChild.remove();
}

function updateCardValue(id, val) {
    const el = document.querySelector(`[data-card-id="${id}"] h2`);
    if (el) el.innerText = val;
}

async function toggleGateway(gateway) {
    try {
        const upiToggle = document.getElementById('upi_toggle');
        const googlePlayToggle = document.getElementById('google_play_toggle');

        const data = await API.getConfig('payment_settings');
        const settings = data.config || {};
        settings.activeGateway = gateway;

        // Sync toggle
        settings.isUpiEnabled = upiToggle.checked;

        await API.updateConfig('payment_settings', settings);
        showSystemToast("Gateway Switched", `Switched to ${gateway.toUpperCase()}`, 'bg-emerald-500');
        loadMonetization();
    } catch (e) {
        showSystemToast("Switch Failed", "Could not change gateway", 'bg-red-500');
    }
}

async function savePaymentSettings(activeGateway) {
    try {
        const upiToggle = document.getElementById('upi_toggle');
        const googlePlayToggle = document.getElementById('google_play_toggle');

        // PREVENT BOTH OFF: If user tries to turn off UPI while Google Play is already off
        if (!upiToggle.checked && !googlePlayToggle.checked) {
            upiToggle.checked = true; // Force it back
            return showSystemToast("Safety Lock", "At least one payment method must remain active", 'bg-orange-500');
        }

        const data = await API.getConfig('payment_settings');
        const settings = data.config || { activeGateway: 'razorpay' };

        // Update Visibility Toggle
        settings.isUpiEnabled = upiToggle.checked;

        if (activeGateway === 'razorpay') {
            settings.razorpay = {
                keyId: document.getElementById('rp_key_id')?.value,
                keySecret: document.getElementById('rp_key_secret')?.value,
                planId: document.getElementById('rp_plan_id')?.value,
                webhookSecret: document.getElementById('rp_webhook_secret')?.value
            };
        } else if (activeGateway === 'phonepe') {
            settings.phonepe = {
                merchantId: document.getElementById('pp_merchant_id')?.value,
                saltKey: document.getElementById('pp_salt_key')?.value,
                saltIndex: document.getElementById('pp_salt_index')?.value,
                webhookSecret: document.getElementById('pp_webhook_secret')?.value,
                env: document.getElementById('pp_env')?.value
            };
        } else if (activeGateway === 'cashfree') {
            settings.cashfree = {
                appId: document.getElementById('cf_app_id')?.value,
                secretKey: document.getElementById('cf_secret_key')?.value,
                env: document.getElementById('cf_env')?.value
            };
        }

        settings.activeGateway = activeGateway;

        await API.updateConfig('payment_settings', settings);
        showSystemToast("UPI Updated", "Payment credentials saved successfully", 'bg-emerald-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Sync Failed", "Could not save credentials", 'bg-red-500');
    }
}

async function saveGooglePlaySettings() {
    try {
        const upiToggle = document.getElementById('upi_toggle');
        const googlePlayToggle = document.getElementById('google_play_toggle');

        // PREVENT BOTH OFF: If user tries to turn off Google Play while UPI is already off
        if (!googlePlayToggle.checked && !upiToggle.checked) {
            googlePlayToggle.checked = true; // Force it back
            return showSystemToast("Safety Lock", "At least one payment method must remain active", 'bg-orange-500');
        }

        let sa = {};
        try {
            sa = JSON.parse(document.getElementById('gp_service_account')?.value || '{}');
        } catch (e) {
            return showSystemToast("Invalid JSON", "Service account must be valid JSON", 'bg-red-500');
        }

        const settings = {
            isEnabled: googlePlayToggle.checked,
            productId: document.getElementById('gp_product_id')?.value,
            trialProductId: document.getElementById('gp_trial_product_id')?.value,
            serviceAccount: sa
        };

        await API.updateConfig('google_play_settings', settings);
        showSystemToast("Google Play Updated", "Billing credentials saved successfully", 'bg-blue-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Sync Failed", "Could not save credentials", 'bg-red-500');
    }
}

async function searchHistory() {
    const val = document.getElementById('historySearch').value;
    loadPaymentHistory(1, val);
}

async function toggleReviewMode(el) {
    const isActive = el.checked;
    const statusText = document.getElementById('reviewModeStatus');

    try {
        await API.updateConfig('review_mode_config', { isReviewMode: isActive });
        statusText.innerText = isActive ? 'Review Mode Active (Payments Hidden)' : 'Live Mode Active (Payments Visible)';
        statusText.className = `text-[9px] font-bold mt-0.5 ${isActive ? 'text-emerald-500' : 'text-slate-500'}`;
        showSystemToast("System Updated", `Compliance Switch ${isActive ? 'ACTIVATED' : 'DEACTIVATED'}`, isActive ? 'bg-red-500' : 'bg-blue-500');
    } catch (e) {
        el.checked = !isActive;
        showSystemToast("Update Failed", "Could not update compliance mode", 'bg-red-500');
    }
}
