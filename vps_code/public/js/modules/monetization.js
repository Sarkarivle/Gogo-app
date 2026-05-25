async function loadMonetization() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Financial Operations & Monetization";
    mainContent.innerHTML = UI.loader();

    try {
        const [configRes, statsRes] = await Promise.all([
            fetch('/api/admin/config/payment_settings'),
            fetch('/api/admin/monetization/stats')
        ]);

        const configData = await configRes.json();
        const statsData = await statsRes.json();

        let settings = configData.config || {};
        // Ensure activeGateway is set to razorpay by default if missing
        if (!settings.activeGateway) settings.activeGateway = 'razorpay';

        let s = statsData.stats || { grossRevenue: 0, todayEarnings: 0, monthlyRevenue: 0, activePremiumUsers: 0, topGateway: 'N/A' };

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade pb-20">
                <!-- Primary Revenue Cards -->
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Gross Revenue', '₹' + s.grossRevenue.toLocaleString(), 'Lifetime Earnings', 'text-emerald-500')}
                    ${UI.card('Today Earnings', '₹' + s.todayEarnings.toLocaleString(), '24h Performance', 'text-orange-500')}
                    ${UI.card('Monthly Revenue', '₹' + s.monthlyRevenue.toLocaleString(), 'Current Period', 'text-blue-500')}
                    ${UI.card('Active Premium', s.activePremiumUsers.toLocaleString(), 'Live Subscriptions', 'text-pink-500')}
                </div>

                <!-- Secondary Financial Metrics -->
                <div class="grid grid-cols-4 gap-6">
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Top Gateway</p>
                        <p class="text-xl font-black text-white uppercase mt-1">${s.topGateway}</p>
                    </div>
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Avg ARPU</p>
                        <p class="text-xl font-black text-white mt-1">₹${s.arpu || 0}</p>
                    </div>
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Failed Today</p>
                        <p class="text-xl font-black text-red-500 mt-1">${s.failedToday || 0}</p>
                    </div>
                    <div class="glass p-6 rounded-3xl">
                        <p class="text-[9px] font-black text-slate-500 uppercase">Churn Rate</p>
                        <p class="text-xl font-black text-white mt-1">${s.subscriptionHealth?.churnRate || '0.0%'}</p>
                    </div>
                </div>

                <div class="grid grid-cols-2 gap-10">
                    <!-- Gateway Config -->
                    <div class="glass p-10 rounded-[3rem] space-y-8 border border-orange-500/10">
                        <div class="border-b border-white/5 pb-6">
                            <h3 class="text-xs font-black text-white uppercase">Infrastructure Control</h3>
                            <p class="text-[8px] text-slate-500 mt-1 uppercase font-bold">Manage payment providers & credentials</p>
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
                            Sync Infrastructure
                        </button>
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
                        ${UI.loader()}
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
                <input type="text" id="rp_key_id" value="${r.keyId || ''}" placeholder="Key ID" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <input type="password" id="rp_key_secret" value="${r.keySecret || ''}" placeholder="Key Secret" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <input type="text" id="rp_plan_id" value="${r.planId || ''}" placeholder="Plan ID" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
                <input type="password" id="rp_webhook_secret" value="${r.webhookSecret || ''}" placeholder="Webhook Secret" class="bg-white/5 border border-white/5 p-3 rounded-xl outline-none text-xs text-white">
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
    return `<p class="text-xs text-slate-500 text-center py-10 uppercase">Config not yet detailed for ${active}</p>`;
}

async function loadPaymentHistory(page = 1, search = '') {
    const container = document.getElementById('historyTable');
    try {
        const res = await fetch(`/api/admin/monetization/history?page=${page}&search=${search}`);
        const data = await res.json();

        const rows = data.transactions.map(t => `
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
        const label = el.previousElementSibling.innerText;
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
                <span class="text-emerald-500 font-black">SUCCESSFUL_PAYMENT</span>
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
    const res = await fetch('/api/admin/config/payment_settings');
    const data = await res.json();
    const settings = data.config || {};
    settings.activeGateway = gateway;

    await fetch('/api/admin/config/update', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key: 'payment_settings', value: settings })
    });
    loadMonetization();
}

async function savePaymentSettings(activeGateway) {
    // Collect from current form
    const settings = {
        activeGateway: activeGateway,
        razorpay: {
            keyId: document.getElementById('rp_key_id')?.value,
            keySecret: document.getElementById('rp_key_secret')?.value,
            planId: document.getElementById('rp_plan_id')?.value,
            webhookSecret: document.getElementById('rp_webhook_secret')?.value
        },
        phonepe: {
            merchantId: document.getElementById('pp_merchant_id')?.value,
            saltKey: document.getElementById('pp_salt_key')?.value,
            saltIndex: document.getElementById('pp_salt_index')?.value,
            webhookSecret: document.getElementById('pp_webhook_secret')?.value,
            env: document.getElementById('pp_env')?.value
        }
    };

    try {
        await fetch('/api/admin/config/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key: 'payment_settings', value: settings })
        });
        alert("Finance Infrastructure Synchronized");
        loadMonetization();
    } catch (err) { alert("Sync Failed"); }
}

async function searchHistory() {
    const val = document.getElementById('historySearch').value;
    loadPaymentHistory(1, val);
}
