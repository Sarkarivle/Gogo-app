let activeMonetizationTab = 'premium';
let activeAdProvider = 'google'; // google, facebook, mediation

async function loadMonetization() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Financial Operations & Monetization";

    mainContent.innerHTML = UI.skeleton(4);

    try {
        const [configData, gpConfigData, reviewData, statsData, adsData, offersData] = await Promise.all([
            API.getConfig('payment_settings').catch(e => ({ success: false, config: {} })),
            API.getConfig('google_play_settings').catch(e => ({ success: false, config: {} })),
            API.getConfig('review_mode_config').catch(e => ({ success: false, config: { isOneMessageTrialEnabled: false } })),
            API.getMonetizationStats().catch(e => ({ success: false, stats: {} })),
            API.getConfig('ads_settings').catch(e => ({ success: false, config: {} })),
            API.getConfig('special_offers').catch(e => ({ success: false, config: { offers: [] } }))
        ]);

        window.monetizationState = {
            settings: configData.config || {},
            gpSettings: gpConfigData.config || {},
            reviewData: reviewData.config || {},
            stats: statsData.stats || {},
            adsSettings: adsData.config || {
                isEnabled: false,
                activeProvider: 'google',
                google: {},
                facebook: {},
                mediation: {}
            },
            offersData: (offersData.config && offersData.config.offers && offersData.config.offers.length > 0) ? offersData.config : {
                offers: [
                    { id: 'daily', name: '1 Day Free', price: 19, duration: 1, rzpPlanId: '', googlePlayId: '', googlePlaySubId: '' },
                    { id: 'weekly', name: '7 Days Access', price: 100, duration: 7, rzpPlanId: '', googlePlayId: '', googlePlaySubId: '' },
                    { id: 'monthly', name: '1 Month Premium', price: 199, duration: 30, rzpPlanId: '', googlePlayId: '', googlePlaySubId: '' }
                ]
            }
        };

        if (window.monetizationState.adsSettings.activeProvider) {
            activeAdProvider = window.monetizationState.adsSettings.activeProvider;
        }

        renderMonetizationUI();
    } catch (err) {
        console.error(err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 font-black uppercase">Monetization Sync Failed</p>`;
    }
}

function renderMonetizationUI() {
    const mainContent = document.getElementById('mainContent');
    const { settings, gpSettings, reviewData, stats, adsSettings } = window.monetizationState;

    mainContent.innerHTML = `
        <div class="space-y-8 animate-fade pb-20">
            <!-- TABS -->
            <div class="flex items-center space-x-4">
                <button onclick="switchMonetizationTab('premium')" class="px-10 py-4 rounded-2xl text-[10px] font-black uppercase tracking-widest transition-all ${activeMonetizationTab === 'premium' ? 'bg-orange-500 text-white shadow-lg shadow-orange-500/20' : 'bg-white/5 text-slate-500 hover:bg-white/10'}">
                    <i class="fas fa-gem mr-2"></i> Premium
                </button>
                <button onclick="switchMonetizationTab('ads')" class="px-10 py-4 rounded-2xl text-[10px] font-black uppercase tracking-widest transition-all ${activeMonetizationTab === 'ads' ? 'bg-orange-500 text-white shadow-lg shadow-orange-500/20' : 'bg-white/5 text-slate-500 hover:bg-white/10'}">
                    <i class="fas fa-ad mr-2"></i> Ads
                </button>
                <button onclick="switchMonetizationTab('offers')" class="px-10 py-4 rounded-2xl text-[10px] font-black uppercase tracking-widest transition-all ${activeMonetizationTab === 'offers' ? 'bg-orange-500 text-white shadow-lg shadow-orange-500/20' : 'bg-white/5 text-slate-500 hover:bg-white/10'}">
                    <i class="fas fa-gift mr-2"></i> Offers
                </button>
                <button onclick="switchMonetizationTab('google_play')" class="px-10 py-4 rounded-2xl text-[10px] font-black uppercase tracking-widest transition-all ${activeMonetizationTab === 'google_play' ? 'bg-orange-500 text-white shadow-lg shadow-orange-500/20' : 'bg-white/5 text-slate-500 hover:bg-white/10'}">
                    <i class="fab fa-google-play mr-2"></i> Google Play Earning
                </button>
            </div>

            <div id="monetizationContent">
                ${activeMonetizationTab === 'premium' ? renderPremiumContent(settings, gpSettings, reviewData, stats) :
                  (activeMonetizationTab === 'ads' ? renderAdsContent(adsSettings) :
                  (activeMonetizationTab === 'offers' ? renderOffersContent() : renderGooglePlayDashboard()))}
            </div>
        </div>
    `;

    if (activeMonetizationTab === 'premium') {
        loadPaymentHistory();
    } else if (activeMonetizationTab === 'google_play') {
        loadGooglePlayData();
    }
}

// --- DATE PICKER LOGIC ---
let gpFilterState = {
    range: 'All Time',
    startDate: '',
    endDate: ''
};

function toggleGPDatePicker() {
    const picker = document.getElementById('gp_date_modal');
    if (picker) {
        picker.classList.toggle('hidden');
        picker.classList.toggle('flex');
    }
}

function selectGPRange(range) {
    gpFilterState.range = range;

    // Update active UI state in dropdown
    document.querySelectorAll('#gp_range_buttons button').forEach(btn => {
        const text = btn.innerText.trim();
        if (text === range) {
            btn.className = "w-full text-left px-6 py-3 rounded-2xl text-[10px] font-black uppercase tracking-widest bg-blue-600 text-white shadow-lg shadow-blue-500/20 transition-all";
        } else {
            btn.className = "w-full text-left px-6 py-3 rounded-2xl text-[10px] font-bold uppercase tracking-widest bg-white/5 text-slate-400 hover:bg-white/10 transition-all";
        }
    });

    const customSection = document.getElementById('gp_modal_custom_inputs');
    if (customSection) {
        if (range === 'Custom Range') customSection.classList.remove('hidden');
        else customSection.classList.add('hidden');
    }
}

function applyGPFilter() {
    const label = document.getElementById('gp_date_label');
    const picker = document.getElementById('gp_date_modal');

    if (gpFilterState.range === 'Custom Range') {
        const start = document.getElementById('gp_modal_start').value;
        const end = document.getElementById('gp_modal_end').value;
        if (!start || !end) {
            showSystemToast("Date Error", "Please select both start and end dates", "bg-red-500");
            return;
        }
        gpFilterState.startDate = start;
        gpFilterState.endDate = end;
        if (label) label.innerText = `${start} to ${end}`;
    } else {
        if (label) label.innerText = gpFilterState.range;
        gpFilterState.startDate = '';
        gpFilterState.endDate = '';
    }

    if (picker) {
        picker.classList.add('hidden');
        picker.classList.remove('flex');
    }
    loadGooglePlayData(1);
}

async function loadGooglePlayData(page = 1, sync = false) {
    const container = document.getElementById('gp_summary_cards');
    if (!container) return;

    if (sync) {
        showSystemToast("Google Sync", "Syncing live data from Google API...", "bg-blue-500");
    }

    try {
        let url = `/api/admin/monetization/google-play-dashboard?page=${page}&limit=20`;
        if (sync) url += '&sync=true';

        if (gpFilterState.range !== 'All Time') {
            url += `&range=${gpFilterState.range}`;
            if (gpFilterState.range === 'Custom Range') {
                url += `&startDate=${gpFilterState.startDate}&endDate=${gpFilterState.endDate}`;
            }
        }

        const data = await API.request(url);
        const { summary, analytics, users, pagination } = data;

        // Update Summary Cards
        document.getElementById('gp_summary_cards').innerHTML = `
            ${UI.card('Gross Revenue', '₹' + summary.lifetimeEarnings.toLocaleString(), 'Selected Period', 'text-emerald-500')}
            ${UI.card('Today Earnings', '₹' + summary.todayEarnings.toLocaleString(), '24h Live (Total)', 'text-orange-500')}
            ${UI.card('Active Premium', summary.activePremium.toLocaleString(), 'Live Subscriptions', 'text-blue-500')}
            ${UI.card('Active Mandate', summary.activeMandates.toLocaleString(), 'Auto-Renew Enabled', 'text-pink-500')}
            ${UI.card('Grace Period', summary.gracePeriod.toLocaleString(), 'In Recovery Window', 'text-yellow-500')}
        `;

        // Update Analytics Visuals
        renderGPAnalytics(analytics);

        // Update User Table
        const rows = users.map(u => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6">
                    <p class="text-white text-xs font-bold underline underline-offset-4 decoration-white/10 cursor-pointer" onclick="openUserControl('${u.phone}')">${u.name}</p>
                    <p class="text-[8px] text-slate-500 uppercase mt-1">${u.phone}</p>
                </td>
                <td class="p-6 text-xs text-emerald-500 font-black">₹${u.subscription?.totalAmountPaid || 0}</td>
                <td class="p-6 text-xs text-white">₹${u.subscription?.lastAmountPaid || 0}</td>
                <td class="p-6">
                    <p class="text-[9px] text-white font-bold">${u.subscription?.lastPaymentDate ? window.formatDateTime(u.subscription.lastPaymentDate).split(',')[0] : 'N/A'}</p>
                    <p class="text-[7px] text-slate-500 uppercase mt-0.5">${u.subscription?.lastPaymentDate ? window.formatDateTime(u.subscription.lastPaymentDate).split(',')[1] : ''}</p>
                </td>
                <td class="p-6 text-[9px] text-slate-400 font-medium">${u.subscription?.nextBillingDate ? window.formatDateTime(u.subscription.nextBillingDate) : 'N/A'}</td>
                <td class="p-6">
                    <div class="flex items-center space-x-2">
                         ${UI.badge(u.subscription?.status || 'N/A', u.subscription?.status === 'active' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}
                         ${u.subscription?.autoRenew ? '<i class="fas fa-sync text-[8px] text-emerald-500 animate-spin-slow"></i>' : '<i class="fas fa-sync-slash text-[8px] text-slate-500"></i>'}
                    </div>
                </td>
                <td class="p-6 text-right">
                    <button onclick="viewGPUserLive('${u.phone}')" class="px-4 py-2 bg-white/5 rounded-xl text-[9px] font-black uppercase hover:bg-orange-500 hover:text-white transition-all">View</button>
                </td>
            </tr>
        `);
        document.getElementById('gp_user_table').innerHTML = UI.table(['User', 'Lifetime', 'Current', 'Purchased At', 'Next Bill', 'Status', 'Action'], rows);

        // Render Pagination
        renderGPPagination(pagination);

    } catch (err) {
        console.error("GP Load Error:", err);
    }
}

function renderGPAnalytics(analytics) {
    const cityContainer = document.getElementById('gp_city_stats');
    if (cityContainer) {
        cityContainer.innerHTML = analytics.topCities.map(c => `
            <div class="space-y-2">
                <div class="flex justify-between text-[9px] font-black uppercase">
                    <span class="text-slate-400">${c._id || 'Unknown'}</span>
                    <span class="text-white">₹${c.total.toLocaleString()}</span>
                </div>
                <div class="w-full h-1 bg-white/5 rounded-full overflow-hidden">
                    <div class="h-full bg-blue-500" style="width: ${Math.min(100, (c.total / 1000) * 100)}%"></div>
                </div>
            </div>
        `).join('');
    }

    const heatContainer = document.getElementById('gp_hourly_heat');
    if (heatContainer) {
        const max = Math.max(...analytics.hourlyHeatmap.map(h => h.total), 1);
        heatContainer.innerHTML = analytics.hourlyHeatmap.map(h => `
            <div class="flex-1 flex flex-col items-center group relative">
                <div class="absolute -top-10 bg-black text-white text-[8px] px-2 py-1 rounded opacity-0 group-hover:opacity-100 transition">₹${h.total}</div>
                <div class="w-full bg-orange-500 rounded-t-sm" style="height: ${(h.total / max) * 100}%; opacity: ${0.2 + (h.total / max) * 0.8}"></div>
                <span class="text-[7px] text-slate-500 font-bold mt-2">${h._id}h</span>
            </div>
        `).join('');
    }
}

function renderGPPagination(pagination) {
    const { page, pages, total } = pagination;
    const container = document.getElementById('gp_pagination');
    if (!container) return;

    if (pages <= 1) {
        container.innerHTML = '';
        return;
    }

    container.innerHTML = `
        <div class="flex items-center justify-between p-8 bg-white/5 border-t border-white/5">
            <p class="text-[9px] font-bold text-slate-500 uppercase">Showing ${Math.min(total, 20)} of ${total} Real Users</p>
            <div class="flex items-center space-x-2">
                <button onclick="loadGooglePlayData(${page - 1})" ${page <= 1 ? 'disabled' : ''} class="px-6 py-2 rounded-xl bg-white/5 text-[9px] font-black uppercase hover:bg-white/10 disabled:opacity-20 transition">Previous</button>
                <span class="px-4 text-[9px] font-black text-white">${page} / ${pages}</span>
                <button onclick="loadGooglePlayData(${page + 1})" ${page >= pages ? 'disabled' : ''} class="px-6 py-2 rounded-xl bg-white/5 text-[9px] font-black uppercase hover:bg-white/10 disabled:opacity-20 transition">Next</button>
            </div>
        </div>
    `;
}

async function viewGPUserLive(phone) {
    UI.modal.show('Live User Intelligence', UI.skeletonModal());

    try {
        const [userData, res] = await Promise.all([
            API.getUserFull(phone),
            API.post('/payment/sync-provider', { phone })
        ]);

        const u = res.success ? res.user : userData.user;
        const sub = u.subscription || {};
        const history = userData.paymentHistory || [];

        // Google Play State Mapping
        const paymentStates = {
            0: { label: 'PENDING RENEWAL', color: 'text-orange-500', desc: 'Google is attempting to charge the next cycle (e.g. ₹199).' },
            1: { label: 'PAYMENT RECEIVED', color: 'text-emerald-500', desc: 'Current cycle payment successfully processed.' },
            2: { label: 'FREE TRIAL / OFFER', color: 'text-blue-500', desc: 'User is currently on an introductory/trial offer.' },
            3: { label: 'PENDING UPGRADE', color: 'text-pink-500', desc: 'User has requested a plan change.' }
        };

        const currentState = paymentStates[sub.googlePaymentState] || { label: 'STABLE', color: 'text-slate-400', desc: 'Subscription is in a normal state.' };

        const historyRows = history.map(t => `
            <tr class="border-b border-white/5">
                <td class="py-4 text-[10px] text-white font-bold">${window.formatDateTime(t.createdAt)}</td>
                <td class="py-4 text-[10px] text-emerald-500 font-black">₹${t.amount}</td>
                <td class="py-4 text-[9px] text-slate-400 font-bold">${t.orderId}</td>
                <td class="py-4">${UI.badge(t.status, t.status === 'SUCCESS' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}</td>
            </tr>
        `).join('');

        const content = `
            <div class="space-y-8 animate-fade max-h-[70vh] overflow-y-auto pr-4 custom-scrollbar">
                <!-- User Profile Summary -->
                <div class="flex items-center space-x-6 p-6 bg-white/5 rounded-3xl border border-white/5">
                    <div class="w-16 h-16 rounded-2xl bg-blue-500/20 flex items-center justify-center">
                        <i class="fas fa-user text-blue-500 text-2xl"></i>
                    </div>
                    <div>
                        <h4 class="text-lg font-black text-white">${u.name}</h4>
                        <p class="text-[10px] text-slate-500 font-bold uppercase tracking-widest">${u.phone}</p>
                    </div>
                    <div class="ml-auto text-right">
                        <p class="text-[9px] font-black text-slate-500 uppercase mb-1">Total Lifetime Paid</p>
                        <p class="text-xl font-black text-emerald-500">₹${sub.totalAmountPaid || 0}</p>
                    </div>
                </div>

                <!-- Google Intelligence Alert -->
                <div class="bg-blue-500/5 border border-blue-500/10 p-6 rounded-3xl flex items-start space-x-4">
                    <div class="p-3 bg-blue-500/10 rounded-2xl">
                        <i class="fas fa-robot text-blue-400"></i>
                    </div>
                    <div>
                        <p class="text-[10px] font-black ${currentState.color} uppercase tracking-widest">${currentState.label}</p>
                        <p class="text-[9px] text-slate-400 font-medium mt-1">${currentState.desc}</p>
                        ${sub.googlePaymentState === 0 ? `<p class="text-[8px] text-orange-400/70 italic mt-2">* Note: Expiry is extended while renewal is pending.</p>` : ''}
                    </div>
                </div>

                <!-- Google Play Live Status -->
                <div class="grid grid-cols-2 gap-6">
                    <div class="glass p-6 rounded-3xl border border-white/5 space-y-4">
                        <p class="text-[9px] font-black text-slate-500 uppercase tracking-widest">Subscription Status</p>
                        <div class="flex items-center justify-between">
                            <span class="text-xs font-black text-white uppercase">${sub.status || 'NONE'}</span>
                            ${UI.badge(sub.status === 'active' ? 'LIVE' : 'INACTIVE', sub.status === 'active' ? 'bg-emerald-500 text-black' : 'bg-red-500/20 text-red-500')}
                        </div>
                        <div class="pt-4 border-t border-white/5 flex items-center justify-between">
                            <span class="text-[8px] text-slate-500 font-bold uppercase">Auto-Renew</span>
                            <i class="fas ${sub.autoRenew ? 'fa-check-circle text-emerald-500' : 'fa-times-circle text-red-500'}"></i>
                        </div>
                    </div>

                    <div class="glass p-6 rounded-3xl border border-white/5 space-y-4">
                        <p class="text-[9px] font-black text-slate-500 uppercase tracking-widest">Next Billing Cycle</p>
                        <p class="text-xs font-black text-white uppercase">${sub.nextBillingDate ? window.formatDateTime(sub.nextBillingDate) : 'N/A'}</p>
                        <div class="pt-4 border-t border-white/5">
                            <p class="text-[8px] text-slate-500 font-bold uppercase">Product: <span class="text-blue-400 ml-1">${sub.planId || 'N/A'}</span></p>
                        </div>
                    </div>
                </div>

                <!-- Transaction Ledger -->
                <div class="space-y-4">
                    <h5 class="text-[10px] font-black text-white uppercase tracking-widest px-2">Payment History</h5>
                    <div class="glass rounded-3xl overflow-hidden">
                        <table class="w-full text-left">
                            <thead class="bg-white/5 text-[8px] font-black uppercase text-slate-500">
                                <tr>
                                    <th class="px-6 py-4">Date</th>
                                    <th class="px-6 py-4">Amount</th>
                                    <th class="px-6 py-4">Order ID</th>
                                    <th class="px-6 py-4">Status</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${historyRows || '<tr><td colspan="4" class="p-10 text-center text-[9px] text-slate-500 uppercase font-bold">No history found</td></tr>'}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        `;

        UI.modal.show(`Intelligence: ${u.name}`, content);
    } catch (e) {
        UI.modal.show('Error', `<p class="p-10 text-center text-red-500 font-black uppercase text-xs">Failed to fetch live intelligence</p>`);
    }
}

function renderGooglePlayDashboard() {
    return `
        <div class="space-y-10 animate-fade">
            <!-- Modal Date Picker (The Center Popup) -->
            <div id="gp_date_modal" class="hidden fixed inset-0 bg-black/80 backdrop-blur-md z-[200] items-center justify-center p-6">
                <div class="bg-[#0a0a0a] w-full max-w-lg rounded-[3rem] border border-white/10 shadow-2xl overflow-hidden animate-zoom">
                    <div class="p-10 space-y-8">
                        <div class="flex justify-between items-center">
                            <h3 class="text-xs font-black text-white uppercase tracking-[0.2em]">Select Period</h3>
                            <button onclick="toggleGPDatePicker()" class="text-slate-500 hover:text-white"><i class="fas fa-times"></i></button>
                        </div>

                        <div id="gp_range_buttons" class="grid grid-cols-2 gap-3">
                            ${['All Time', 'Today', 'Yesterday', 'Last 7 Days', 'This Month', 'Last Month', 'Custom Range'].map(range => `
                                <button onclick="selectGPRange('${range}')" class="w-full text-left px-6 py-3 rounded-2xl text-[10px] font-bold uppercase tracking-widest transition-all ${gpFilterState.range === range ? 'bg-blue-600 text-white shadow-lg' : 'bg-white/5 text-slate-400 hover:bg-white/10'}">
                                    ${range}
                                </button>
                            `).join('')}
                        </div>

                        <div id="gp_modal_custom_inputs" class="${gpFilterState.range === 'Custom Range' ? '' : 'hidden'} space-y-6 pt-8 border-t border-white/5">
                            <div class="grid grid-cols-2 gap-6">
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Start Date</label>
                                    <input type="date" id="gp_modal_start" class="w-full bg-black border border-white/10 p-4 rounded-2xl text-[11px] text-white outline-none focus:border-blue-500 mt-2" value="${gpFilterState.startDate}">
                                </div>
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">End Date</label>
                                    <input type="date" id="gp_modal_end" class="w-full bg-black border border-white/10 p-4 rounded-2xl text-[11px] text-white outline-none focus:border-blue-500 mt-2" value="${gpFilterState.endDate}">
                                </div>
                            </div>
                        </div>

                        <div class="flex space-x-4 pt-4 border-t border-white/5">
                            <button onclick="applyGPFilter()" class="flex-1 py-4 bg-blue-600 text-white rounded-2xl text-[10px] font-black uppercase shadow-xl shadow-blue-600/40 hover:scale-[1.02] transition active:scale-95">Apply Filter</button>
                            <button onclick="toggleGPDatePicker()" class="px-8 py-4 bg-white/5 text-slate-400 rounded-2xl text-[10px] font-black uppercase hover:bg-white/10 transition">Close</button>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Header & Action -->
            <div class="glass p-8 rounded-[2rem] border border-blue-500/10 bg-gradient-to-br from-blue-500/5 to-transparent flex justify-between items-center">
                <div class="flex items-center space-x-4">
                    <div class="w-12 h-12 bg-blue-500 rounded-2xl flex items-center justify-center shadow-lg shadow-blue-500/20">
                        <i class="fab fa-google-play text-white text-xl"></i>
                    </div>
                    <div>
                        <h3 class="text-sm font-black text-white uppercase tracking-widest">Google Play Intelligence</h3>
                        <p class="text-[10px] text-slate-500 uppercase font-bold mt-1">Live Revenue & Subscription Mandate Tracking</p>
                    </div>
                </div>
                <div class="flex items-center space-x-4">
                    <button onclick="toggleGPDatePicker()" class="bg-black/60 px-8 py-3.5 rounded-2xl border border-white/10 flex items-center space-x-3 hover:bg-blue-600/10 hover:border-blue-500/30 transition shadow-2xl group">
                        <i class="fas fa-calendar-day text-blue-500 text-[10px] group-hover:scale-110 transition"></i>
                        <span id="gp_date_label" class="text-[10px] font-black text-white uppercase tracking-[0.1em]">${gpFilterState.range === 'Custom Range' ? (gpFilterState.startDate + ' — ' + gpFilterState.endDate) : gpFilterState.range}</span>
                        <i class="fas fa-chevron-down text-[8px] text-slate-500"></i>
                    </button>

                    <button onclick="loadGooglePlayData(1, true)" class="p-4 bg-white/5 hover:bg-white/10 rounded-2xl text-white transition shadow-xl active:rotate-180">
                        <i class="fas fa-sync-alt"></i>
                    </button>
                </div>
            </div>

            <!-- Primary Revenue Cards -->
            <div id="gp_summary_cards" class="grid grid-cols-5 gap-6">
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
            </div>

            <div class="grid grid-cols-2 gap-10">
                <!-- Analytics Section -->
                <div class="glass p-10 rounded-[3rem] border border-white/5 space-y-10">
                    <div>
                        <h3 class="text-[10px] font-black text-white uppercase tracking-widest mb-6"><i class="fas fa-map-marker-alt mr-2 text-blue-500"></i> Top Revenue Cities</h3>
                        <div id="gp_city_stats" class="space-y-6">
                            ${UI.skeleton(3)}
                        </div>
                    </div>

                    <div class="pt-10 border-t border-white/5">
                        <h3 class="text-[10px] font-black text-white uppercase tracking-widest mb-8"><i class="fas fa-clock mr-2 text-orange-500"></i> Hourly Revenue Heatmap</h3>
                        <div id="gp_hourly_heat" class="h-32 flex items-end space-x-2">
                             ${Array.from({length: 24}).map(() => `<div class="flex-1 bg-white/5 rounded-t-sm h-4"></div>`).join('')}
                        </div>
                    </div>
                </div>

                <!-- Marketing Insights -->
                <div class="glass p-10 rounded-[3rem] border border-white/5 space-y-8">
                    <h3 class="text-[10px] font-black text-white uppercase tracking-widest"><i class="fas fa-bullseye mr-2 text-pink-500"></i> Marketing Growth Insights</h3>

                    <div class="grid grid-cols-1 gap-4">
                        <div class="p-6 bg-white/[0.02] rounded-3xl border border-white/5 flex items-center justify-between">
                            <div>
                                <p class="text-[10px] font-black text-white uppercase">Subscription Retention</p>
                                <p class="text-[8px] text-slate-500 uppercase font-bold mt-1">Churn rate is lower by 2.4% this week</p>
                            </div>
                            <i class="fas fa-chart-line text-emerald-500"></i>
                        </div>

                        <div class="p-6 bg-white/[0.02] rounded-3xl border border-white/5 flex items-center justify-between">
                            <div>
                                <p class="text-[10px] font-black text-white uppercase">Failed Recovery</p>
                                <p class="text-[8px] text-slate-500 uppercase font-bold mt-1">12 Users can be recovered with a discount</p>
                            </div>
                            <button class="px-4 py-2 bg-orange-500 text-white text-[8px] font-black rounded-lg uppercase">Send Offer</button>
                        </div>

                         <div class="p-6 bg-blue-500/5 rounded-3xl border border-blue-500/10">
                            <p class="text-[10px] font-black text-blue-400 uppercase mb-2">Campaign Tip</p>
                            <p class="text-[9px] text-slate-400 leading-relaxed font-medium italic">"Users from Lucknow have 40% higher conversion. Consider increasing ad spend for this region between 8 PM - 11 PM."</p>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Ledger Table -->
            <div class="glass rounded-[3rem] overflow-hidden">
                <div class="p-8 border-b border-white/5 bg-white/5 flex justify-between items-center">
                     <h3 class="text-xs font-black text-white uppercase tracking-widest">Google Play Transaction Ledger</h3>
                     <div class="flex items-center space-x-4">
                        <input type="text" id="gpUserSearch" placeholder="Search Mobile / Name" class="bg-black/20 border border-white/5 px-4 py-2 rounded-xl text-[10px] text-white outline-none w-64 focus:border-blue-500/50">
                        <button onclick="loadGooglePlayData(1)" class="px-6 py-2 bg-white/5 rounded-xl text-[10px] font-black uppercase hover:bg-white/10 transition">Search</button>
                     </div>
                </div>
                <div id="gp_user_table">
                    ${UI.skeletonTable(10)}
                </div>
                <div id="gp_pagination"></div>
            </div>
        </div>
    `;
}

function switchMonetizationTab(tab) {
    activeMonetizationTab = tab;
    renderMonetizationUI();
}

function renderPremiumContent(settings, gpSettings, reviewData, statsRaw) {
    if (!settings.activeGateway) settings.activeGateway = 'razorpay';

    const stats = {
        grossRevenue: statsRaw.grossRevenue || 0,
        todayEarnings: statsRaw.todayEarnings || 0,
        monthlyRevenue: statsRaw.monthlyRevenue || 0,
        activePremiumUsers: statsRaw.activePremiumUsers || 0,
        topGateway: statsRaw.topGateway || 'N/A',
        arpu: statsRaw.arpu || 0,
        failedToday: statsRaw.failedToday || 0,
        subscriptionHealth: statsRaw.subscriptionHealth || { churnRate: '0.0%' }
    };

    return `
        <div class="space-y-10 animate-fade">
            <!-- Advanced Monetization Logic -->
            <div class="glass p-8 rounded-[2rem] border border-white/5 bg-gradient-to-br from-white/5 to-transparent">
                <div class="grid grid-cols-1 md:grid-cols-1 gap-8">

                    <!-- Message Trial Limit -->
                    <div class="space-y-4">
                        <div class="flex items-center space-x-3">
                            <div class="p-2 bg-orange-500/10 rounded-xl">
                                <i class="fas fa-comment-alt-dots text-orange-500"></i>
                            </div>
                            <h3 class="text-[10px] font-black text-white uppercase tracking-widest">Freemium Message Limit</h3>
                        </div>
                        <div class="bg-black/20 p-4 rounded-2xl border border-white/5 flex items-center justify-between">
                            <div>
                                <p class="text-[9px] font-bold ${reviewData?.isOneMessageTrialEnabled ? 'text-orange-500' : 'text-slate-500'}">
                                    ${reviewData?.isOneMessageTrialEnabled ? 'LIMIT ENABLED' : 'LIMIT DISABLED'}
                                </p>
                                <input type="number" id="free_message_limit" value="${reviewData?.freeMessageLimit || 1}" class="w-12 bg-transparent text-[10px] text-white font-bold outline-none border-b border-white/20 focus:border-orange-500 mt-1">
                            </div>
                            <label class="relative inline-flex items-center cursor-pointer scale-110">
                                <input type="checkbox" id="one_message_trial_toggle" ${reviewData?.isOneMessageTrialEnabled ? 'checked' : ''} onchange="toggleOneMessageTrial(this)" class="sr-only peer">
                                <div class="w-12 h-6 bg-white/10 rounded-full peer peer-checked:bg-orange-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:after:translate-x-6"></div>
                            </label>
                        </div>
                    </div>

                </div>

                <div class="mt-6 pt-6 border-t border-white/5 flex items-center justify-between">
                    <div class="flex items-center space-x-2 text-[8px] text-slate-500 font-bold uppercase italic">
                        <i class="fas fa-info-circle text-blue-500"></i>
                        <span>Status: Global Live (Everyone will be prompted to pay after trial)</span>
                    </div>
                </div>
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

                        <div class="grid grid-cols-2 gap-6">
                             <div>
                                <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Standard Plan ID (RZP)</label>
                                <input type="text" id="rzp_plan_id" value="${settings.razorpay?.planId || settings.planId || ''}" placeholder="plan_Nxxxx" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-white mt-2">
                            </div>
                             <div>
                                <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Standard Plan ID (GP)</label>
                                <input type="text" id="gp_standard_plan_id" value="${gpSettings.productId || ''}" placeholder="premium_subscription" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-white mt-2">
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

                <!-- Google Play Integration (Replaced Financial Intelligence) -->
                <div class="glass p-10 rounded-[3rem] space-y-8 border border-blue-500/10">
                    <div class="border-b border-white/5 pb-6">
                        <h3 class="text-xs font-black text-white uppercase tracking-widest">Google Play Billing</h3>
                        <p class="text-[8px] text-slate-500 mt-1 uppercase font-bold">In-app purchase settings</p>
                    </div>
                    <div class="space-y-6">
                        <div class="flex items-center justify-between glass p-4 rounded-2xl">
                            <div>
                                <p class="text-[10px] font-black text-white uppercase">Enable Play Billing</p>
                            </div>
                            <label class="relative inline-flex items-center cursor-pointer">
                                <input type="checkbox" id="gp_enabled" ${gpSettings.isEnabled ? 'checked' : ''} class="sr-only peer">
                                <div class="w-11 h-6 bg-white/10 rounded-full peer peer-checked:bg-blue-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:after:translate-x-5"></div>
                            </label>
                        </div>
                        <div>
                            <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Subscription Product ID</label>
                            <input type="text" id="gp_product_id" value="${gpSettings.productId || ''}" placeholder="premium_subscription" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-white mt-2">
                        </div>
                        <div>
                            <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Service Account Key (JSON)</label>
                            <textarea id="gp_service_key" rows="8" placeholder='{ "type": "service_account", ... }' class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-slate-400 font-mono mt-2">${gpSettings.serviceAccountKey || ''}</textarea>
                        </div>
                        <button onclick="saveGooglePlaySettings()" class="w-full py-4 bg-blue-500/10 text-blue-500 border border-blue-500/20 rounded-xl text-[10px] font-black uppercase hover:bg-blue-500 hover:text-white transition">
                            Update Google Play Config
                        </button>
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
}

function renderAdsContent(ads) {
    const google = ads.google || {};
    const facebook = ads.facebook || {};
    const mediation = ads.mediation || {};

    return `
        <div class="animate-fade space-y-10">
            <!-- Global Ad Engine Controls -->
            <div class="glass p-8 rounded-[2rem] border border-orange-500/20 bg-gradient-to-br from-orange-500/5 to-transparent">
                <div class="flex items-center justify-between">
                    <div class="flex items-center space-x-4">
                        <div class="w-12 h-12 bg-orange-500 rounded-2xl flex items-center justify-center shadow-lg shadow-orange-500/20">
                            <i class="fas fa-tower-broadcast text-black text-xl"></i>
                        </div>
                        <div>
                            <h3 class="text-sm font-black text-white uppercase tracking-widest">Unified Ad Engine</h3>
                            <p class="text-[10px] text-slate-500 uppercase font-bold mt-1">Select your active traffic monetization strategy</p>
                        </div>
                    </div>

                    <div class="flex items-center space-x-6">
                        <div class="flex bg-black/40 p-1.5 rounded-2xl border border-white/5">
                            ${['google', 'facebook', 'mediation'].map(p => `
                                <button onclick="switchAdProvider('${p}')" class="px-6 py-2.5 rounded-xl text-[9px] font-black uppercase tracking-widest transition-all ${activeAdProvider === p ? 'bg-orange-500 text-white shadow-lg' : 'text-slate-500 hover:text-white'}">
                                    ${p === 'google' ? 'AdMob/AdX' : (p === 'facebook' ? 'Facebook' : 'Mediation')}
                                </button>
                            `).join('')}
                        </div>

                        <div class="h-10 w-px bg-white/10 mx-2"></div>

                        <div class="flex items-center space-x-3 bg-white/5 px-6 py-3 rounded-2xl border border-white/5">
                             <span class="text-[9px] font-black text-white uppercase">Master Switch</span>
                             <label class="relative inline-flex items-center cursor-pointer">
                                <input type="checkbox" id="ads_enabled" ${ads.isEnabled ? 'checked' : ''} class="sr-only peer">
                                <div class="w-11 h-6 bg-white/10 rounded-full peer peer-checked:bg-orange-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:after:translate-x-5"></div>
                            </label>
                        </div>
                    </div>
                </div>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-10">
                <!-- Dynamic Provider Form -->
                <div class="glass p-10 rounded-[3rem] space-y-8 border border-white/5 relative overflow-hidden">
                    <div id="providerIcon" class="absolute -top-10 -right-10 opacity-5 pointer-events-none">
                         <i class="fas ${activeAdProvider === 'google' ? 'fa-google' : (activeAdProvider === 'facebook' ? 'fa-facebook' : 'fa-layer-group')} text-[15rem]"></i>
                    </div>

                    <div class="border-b border-white/5 pb-6">
                        <h3 class="text-xs font-black text-white uppercase tracking-widest">${activeAdProvider.toUpperCase()} CONFIGURATION</h3>
                        <p class="text-[8px] text-slate-500 mt-1 uppercase font-bold">Manage units for ${activeAdProvider === 'google' ? 'AdMob & AdX' : activeAdProvider}</p>
                    </div>

                    <div id="adProviderForm" class="space-y-6">
                        ${renderAdProviderFields(activeAdProvider, ads)}
                    </div>

                    <button onclick="saveAdsSettings()" class="w-full py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-orange-500/30">
                        <i class="fas fa-save mr-2"></i> Sync ${activeAdProvider} Settings
                    </button>
                </div>

                <!-- Ad Controls & Targeting -->
                <div class="space-y-8">
                    <div class="glass p-10 rounded-[3rem] space-y-8 border border-white/5">
                        <div class="border-b border-white/5 pb-6">
                            <h3 class="text-xs font-black text-white uppercase tracking-widest">Global Visibility Rules</h3>
                        </div>

                        <div class="space-y-4">
                            <div class="flex items-center justify-between glass p-5 rounded-2xl bg-white/[0.02]">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase tracking-wider">Ads for Free Users Only</p>
                                    <p class="text-[8px] text-slate-500 uppercase font-bold mt-0.5">Premium users will never see ads</p>
                                </div>
                                <label class="relative inline-flex items-center cursor-pointer">
                                    <input type="checkbox" id="ads_free_users_only" ${ads.freeUsersOnly !== false ? 'checked' : ''} class="sr-only peer">
                                    <div class="w-10 h-5 bg-white/10 rounded-full peer peer-checked:bg-emerald-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-5"></div>
                                </label>
                            </div>

                            <div class="flex items-center justify-between glass p-5 rounded-2xl bg-white/[0.02]">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase tracking-wider">Interstitials on App Start</p>
                                    <p class="text-[8px] text-slate-500 uppercase font-bold mt-0.5">Trigger ad as soon as splash finishes</p>
                                </div>
                                <label class="relative inline-flex items-center cursor-pointer">
                                    <input type="checkbox" id="ads_on_start" ${ads.showOnStart ? 'checked' : ''} class="sr-only peer">
                                    <div class="w-10 h-5 bg-white/10 rounded-full peer peer-checked:bg-emerald-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:after:translate-x-5"></div>
                                </label>
                            </div>

                             <div class="flex items-center justify-between glass p-5 rounded-2xl bg-white/[0.02]">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase tracking-wider">Ad Frequency Capping</p>
                                    <p class="text-[8px] text-slate-500 uppercase font-bold mt-0.5">Minutes between Interstitials</p>
                                </div>
                                <input type="number" id="ads_frequency" value="${ads.frequencyMinutes || 5}" class="w-16 bg-black/40 border border-white/10 rounded-lg p-2 text-xs text-white text-center outline-none focus:border-orange-500">
                            </div>

                            <div class="pt-6 border-t border-white/5 space-y-6">
                                <h4 class="text-[10px] font-black text-orange-500 uppercase tracking-widest">Rewarded Ad Triggers & Limits</h4>
                                <div class="grid grid-cols-2 gap-4">
                                    <div>
                                        <p class="text-[7px] text-slate-500 mb-1">MIN MESSAGES (FOR POPUP)</p>
                                        <input type="number" id="reward_min_msg" value="${ads.rewardMinMsg || 4}" class="w-full bg-black/20 border border-white/5 p-3 rounded-xl text-xs text-white">
                                    </div>
                                    <div>
                                        <p class="text-[7px] text-slate-500 mb-1">MAX MESSAGES (FOR POPUP)</p>
                                        <input type="number" id="reward_max_msg" value="${ads.rewardMaxMsg || 7}" class="w-full bg-black/20 border border-white/5 p-3 rounded-xl text-xs text-white">
                                    </div>
                                </div>
                                <div class="grid grid-cols-2 gap-4">
                                    <div>
                                        <p class="text-[7px] text-slate-500 mb-1">REWARD DURATION (MINUTES)</p>
                                        <input type="number" id="reward_duration" value="${ads.rewardDurationMinutes || 60}" class="w-full bg-black/20 border border-white/5 p-3 rounded-xl text-xs text-white">
                                    </div>
                                    <div>
                                        <p class="text-[7px] text-slate-500 mb-1">DAILY REWARD LIMIT</p>
                                        <input type="number" id="reward_daily_limit" value="${ads.rewardDailyLimit || 5}" class="w-full bg-black/20 border border-white/5 p-3 rounded-xl text-xs text-white">
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Setup Guide -->
            <div class="glass p-8 rounded-[3rem] border border-blue-500/10 bg-blue-500/5">
                <div class="flex items-center space-x-3 mb-4">
                    <i class="fas fa-circle-info text-blue-500 text-sm"></i>
                    <h4 class="text-[10px] font-black text-white uppercase tracking-widest">Implementation Guide</h4>
                </div>
                <ul class="space-y-3">
                    <li class="flex items-start space-x-3">
                        <div class="w-4 h-4 rounded-full bg-blue-500/20 flex items-center justify-center shrink-0 mt-0.5"><span class="text-[8px] font-bold text-blue-500">1</span></div>
                        <p class="text-[9px] text-slate-400 font-medium">For **AdX Manager**, use the same fields as AdMob but enter your GAM/AdX Ad Unit paths.</p>
                    </li>
                    <li class="flex items-start space-x-3">
                        <div class="w-4 h-4 rounded-full bg-blue-500/20 flex items-center justify-center shrink-0 mt-0.5"><span class="text-[8px] font-bold text-blue-500">2</span></div>
                        <p class="text-[9px] text-slate-400 font-medium">**Mediation Mode** expects you to use AdMob/GAM as the primary host with FAN integrated via bidding.</p>
                    </li>
                </ul>
            </div>
        </div>
    `;
}

function renderAdProviderFields(provider, allAds) {
    const data = allAds[provider] || {};

    if (provider === 'google') {
        return `
            <div>
                <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">App ID (AdMob/AdX)</label>
                <input type="text" id="ad_google_app_id" value="${data.appId || ''}" placeholder="ca-app-pub-xxx~xxx" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-white mt-2 focus:border-orange-500/50 transition">
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Interstitial Unit ID</label>
                    <input type="text" id="ad_google_interstitial" value="${data.interstitialId || ''}" placeholder="ca-app-pub-xxx/xxx" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Banner Unit ID</label>
                    <input type="text" id="ad_google_banner" value="${data.bannerId || ''}" placeholder="ca-app-pub-xxx/xxx" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Native Ad Unit ID</label>
                    <input type="text" id="ad_google_native" value="${data.nativeId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Rewarded Ad Unit ID</label>
                    <input type="text" id="ad_google_rewarded" value="${data.rewardedId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
            </div>
        `;
    } else if (provider === 'facebook') {
        return `
            <div>
                <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Facebook App ID</label>
                <input type="text" id="ad_fb_app_id" value="${data.appId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-white mt-2">
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Placement: Interstitial</label>
                    <input type="text" id="ad_fb_interstitial" value="${data.interstitialId || ''}" placeholder="IMG_16_9_APP_INSTALL#xxx" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
                <div>
                    <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Placement: Banner</label>
                    <input type="text" id="ad_fb_banner" value="${data.bannerId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Placement: Native</label>
                    <input type="text" id="ad_fb_native" value="${data.nativeId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
                <div>
                    <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Placement: Rewarded</label>
                    <input type="text" id="ad_fb_rewarded" value="${data.rewardedId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
            </div>
        `;
    } else if (provider === 'mediation') {
        return `
            <div class="bg-blue-500/10 p-6 rounded-2xl border border-blue-500/20 mb-6">
                <p class="text-[10px] text-blue-400 font-bold uppercase leading-relaxed">
                    <i class="fas fa-info-circle mr-2"></i> Mediation is powered by Google AdMob/AdX.
                    Ensure you have linked Facebook Audience Network in your Google Console bidding/waterfall.
                </p>
            </div>
            <div>
                <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Mediation App ID (Primary)</label>
                <input type="text" id="ad_med_app_id" value="${data.appId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-white mt-2">
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Mediation: Interstitial</label>
                    <input type="text" id="ad_med_interstitial" value="${data.interstitialId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Mediation: Banner</label>
                    <input type="text" id="ad_med_banner" value="${data.bannerId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
            </div>
            <div class="grid grid-cols-2 gap-4">
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Mediation: Native</label>
                    <input type="text" id="ad_med_native" value="${data.nativeId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
                <div>
                    <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Mediation: Rewarded</label>
                    <input type="text" id="ad_med_rewarded" value="${data.rewardedId || ''}" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-xs text-white mt-2">
                </div>
            </div>
        `;
    }
}

function switchAdProvider(p) {
    activeAdProvider = p;
    renderMonetizationUI();
}

async function saveAdsSettings() {
    try {
        const ads = window.monetizationState.adsSettings;

        ads.isEnabled = document.getElementById('ads_enabled').checked;
        ads.freeUsersOnly = document.getElementById('ads_free_users_only').checked;
        ads.showOnStart = document.getElementById('ads_on_start').checked;
        ads.frequencyMinutes = parseInt(document.getElementById('ads_frequency').value) || 5;
        ads.rewardMinMsg = parseInt(document.getElementById('reward_min_msg').value) || 4;
        ads.rewardMaxMsg = parseInt(document.getElementById('reward_max_msg').value) || 7;
        ads.rewardDurationMinutes = parseInt(document.getElementById('reward_duration').value) || 60;
        ads.rewardDailyLimit = parseInt(document.getElementById('reward_daily_limit').value) || 5;
        ads.activeProvider = activeAdProvider;

        if (activeAdProvider === 'google') {
            ads.google = {
                appId: document.getElementById('ad_google_app_id').value,
                interstitialId: document.getElementById('ad_google_interstitial').value,
                bannerId: document.getElementById('ad_google_banner').value,
                nativeId: document.getElementById('ad_google_native').value,
                rewardedId: document.getElementById('ad_google_rewarded').value
            };
        } else if (activeAdProvider === 'facebook') {
            ads.facebook = {
                appId: document.getElementById('ad_fb_app_id').value,
                interstitialId: document.getElementById('ad_fb_interstitial').value,
                bannerId: document.getElementById('ad_fb_banner').value,
                nativeId: document.getElementById('ad_fb_native').value,
                rewardedId: document.getElementById('ad_fb_rewarded').value
            };
        } else if (activeAdProvider === 'mediation') {
            ads.mediation = {
                appId: document.getElementById('ad_med_app_id').value,
                interstitialId: document.getElementById('ad_med_interstitial').value,
                bannerId: document.getElementById('ad_med_banner').value,
                nativeId: document.getElementById('ad_med_native').value,
                rewardedId: document.getElementById('ad_med_rewarded').value
            };
        }

        await API.updateConfig('ads_settings', ads);
        showSystemToast("Ads Synced", `${activeAdProvider.toUpperCase()} config broadcasted to app`, 'bg-orange-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "API communication error", 'bg-red-500');
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
        const rzpPlanId = document.getElementById('rzp_plan_id').value;
        const gpPlanId = document.getElementById('gp_standard_plan_id').value;

        const [payRes, gpRes] = await Promise.all([
            API.getConfig('payment_settings'),
            API.getConfig('google_play_settings')
        ]);

        const settings = payRes.config || {};
        const gpSettings = gpRes.config || {};

        settings.trialPrice = parseInt(trialVal) || 1;
        settings.monthlyPrice = parseInt(monthlyVal) || 199;
        settings.planId = rzpPlanId;
        if (settings.razorpay) settings.razorpay.planId = rzpPlanId;

        gpSettings.productId = gpPlanId;

        await Promise.all([
            API.updateConfig('payment_settings', settings),
            API.updateConfig('google_play_settings', gpSettings)
        ]);

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

async function saveGooglePlaySettings() {
    try {
        const config = {
            isEnabled: document.getElementById('gp_enabled').checked,
            productId: document.getElementById('gp_product_id').value,
            serviceAccountKey: document.getElementById('gp_service_key').value
        };
        await API.updateConfig('google_play_settings', config);
        showSystemToast("Google Play Updated", "Configuration saved", 'bg-blue-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "Update failed", 'bg-red-500');
    }
}

function renderOffersContent() {
    const { offersData } = window.monetizationState;
    const offers = offersData.offers || [];

    return `
        <div class="animate-fade space-y-10">
            <div class="glass p-8 rounded-[2rem] border border-pink-500/20 bg-gradient-to-br from-pink-500/5 to-transparent">
                <div class="flex items-center justify-between">
                    <div class="flex items-center space-x-4">
                        <div class="w-12 h-12 bg-pink-500 rounded-2xl flex items-center justify-center shadow-lg shadow-pink-500/20">
                            <i class="fas fa-gift text-white text-xl"></i>
                        </div>
                        <div>
                            <h3 class="text-sm font-black text-white uppercase tracking-widest">Special Offers & Bundles</h3>
                            <p class="text-[10px] text-slate-500 uppercase font-bold mt-1">Configure retention and trial offers</p>
                        </div>
                    </div>
                    <button onclick="saveOffersSettings()" class="px-8 py-3 bg-pink-500 text-white rounded-xl text-[10px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-pink-500/30">
                        <i class="fas fa-save mr-2"></i> Sync All Offers
                    </button>
                </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
                ${offers.map((offer, idx) => `
                    <div class="glass p-8 rounded-[2.5rem] border border-white/5 space-y-6">
                        <div class="flex justify-between items-center">
                             <span class="px-3 py-1 bg-white/5 rounded-full text-[8px] font-black text-slate-500 uppercase tracking-widest">Offer #${idx + 1}</span>
                             <i class="fas fa-bolt text-pink-500"></i>
                        </div>

                        <div class="space-y-4">
                            <div>
                                <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Offer Name</label>
                                <input type="text" id="offer_name_${idx}" value="${offer.name}" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[11px] text-white mt-1">
                            </div>
                            <div class="grid grid-cols-2 gap-4">
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Price (₹)</label>
                                    <input type="number" id="offer_price_${idx}" value="${offer.price}" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[11px] text-emerald-500 font-bold mt-1">
                                </div>
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Days</label>
                                    <input type="number" id="offer_days_${idx}" value="${offer.duration}" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[11px] text-white mt-1">
                                </div>
                            </div>
                            <div class="grid grid-cols-2 gap-4">
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Razorpay Plan ID</label>
                                    <input type="text" id="offer_rzp_id_${idx}" value="${offer.rzpPlanId || ''}" placeholder="plan_xxx" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[10px] text-orange-400 mt-1">
                                </div>
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Google Play Sub ID (Product)</label>
                                    <input type="text" id="offer_gp_sub_id_${idx}" value="${offer.googlePlaySubId || 'gogo_monthly_199'}" placeholder="gogo_monthly_199" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[10px] text-blue-400 mt-1">
                                </div>
                            </div>
                            <div>
                                <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Google Play Base/Offer ID</label>
                                <input type="text" id="offer_gp_id_${idx}" value="${offer.googlePlayId || ''}" placeholder="gogo-19-rs-offer" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-emerald-400 mt-1">
                            </div>
                        </div>
                    </div>
                `).join('')}
            </div>
        </div>
    `;
}

async function saveOffersSettings() {
    try {
        const offers = [];
        for (let i = 0; i < 3; i++) {
            offers.push({
                id: i === 0 ? 'daily' : (i === 1 ? 'weekly' : 'monthly'),
                name: document.getElementById(`offer_name_${i}`).value,
                price: parseInt(document.getElementById(`offer_price_${i}`).value) || 0,
                duration: parseInt(document.getElementById(`offer_days_${i}`).value) || 0,
                rzpPlanId: document.getElementById(`offer_rzp_id_${i}`).value,
                googlePlaySubId: document.getElementById(`offer_gp_sub_id_${i}`).value,
                googlePlayId: document.getElementById(`offer_gp_id_${i}`).value
            });
        }

        await API.updateConfig('special_offers', { offers });
        showSystemToast("Offers Updated", "Special plans broadcasted to app", 'bg-pink-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "API communication error", 'bg-red-500');
    }
}

async function toggleOneMessageTrial(el) {
    try {
        const reviewData = await API.getConfig('review_mode_config').catch(e => ({ success: false, config: {} }));
        const config = reviewData.config || {};
        config.isOneMessageTrialEnabled = el.checked;
        config.freeMessageLimit = parseInt(document.getElementById('free_message_limit').value) || 1;

        await API.updateConfig('review_mode_config', config);

        showSystemToast("Trial Config Updated", `Message Limit: ${config.freeMessageLimit} (${el.checked ? 'ENABLED' : 'DISABLED'})`, 'bg-orange-500');
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
    if (!container) return; // Silent return if we are in another tab

    try {
        const data = await API.getPaymentHistory(page);
        const filtered = search ? data.transactions.filter(t => t.userPhone.includes(search) || t.orderId.includes(search)) : data.transactions;
        const rows = filtered.map(t => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6">
                    <p onclick="openUserControl('${t.userPhone}')" class="text-white text-xs font-bold cursor-pointer hover:text-orange-500 transition-all underline decoration-white/10 underline-offset-4">${t.userPhone}</p>
                    <p class="text-[8px] text-slate-500 uppercase mt-1">${t.orderId}</p>
                </td>
                <td class="p-6 text-xs font-black text-white">₹${t.amount}</td>
                <td class="p-6">${UI.badge(t.status, t.status === 'SUCCESS' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}</td>
                <td class="p-6 text-[10px] text-slate-500 font-bold uppercase">${t.gateway}</td>
                <td class="p-6 text-[9px] text-slate-400 font-medium">${window.formatDateTime(t.createdAt)}</td>
            </tr>
        `);
        container.innerHTML = UI.table(['Customer', 'Amount', 'Status', 'Gateway', 'Timestamp'], rows);
    } catch (e) { }
}

async function searchHistory() {
    loadPaymentHistory(1, document.getElementById('historySearch').value);
}

