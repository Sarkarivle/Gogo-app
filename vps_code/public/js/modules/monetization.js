let activeMonetizationTab = 'premium';
let activeAdProvider = 'google';

async function loadMonetization() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Financial Operations & Monetization";

    mainContent.innerHTML = UI.skeleton(4);

    try {
        const [configData, gpConfigData, statsData, adsData, offersData, reviewData] = await Promise.all([
            API.getConfig('payment_settings').catch(e => ({ success: false, config: {} })),
            API.getConfig('google_play_settings').catch(e => ({ success: false, config: {} })),
            API.getMonetizationStats().catch(e => ({ success: false, stats: {} })),
            API.getConfig('ads_settings').catch(e => ({ success: false, config: {} })),
            API.getConfig('special_offers').catch(e => ({ success: false, config: { offers: [] } })),
            API.getConfig('review_mode_config').catch(e => ({ success: false, config: {} }))
        ]);

        window.monetizationState = {
            settings: configData.config || {},
            gpSettings: gpConfigData.config || {},
            stats: statsData.stats || {},
            reviewData: reviewData.config || {},
            adsSettings: adsData.config || {
                isEnabled: false,
                activeProvider: 'google',
                google: {},
                facebook: {},
                mediation: {}
            },
            offersData: (offersData.config && offersData.config.offers && offersData.config.offers.length > 0) ? offersData.config : {
                offers: [
                    { id: 'weekly', name: '7 Days Access', price: 99, duration: 7, rzpPlanId: '', googlePlayId: '', googlePlaySubId: '' },
                    { id: 'monthly', name: '1 Month Premium', price: 199, duration: 30, rzpPlanId: '', googlePlayId: '', googlePlaySubId: '' },
                    { id: 'quarterly', name: '3 Months Premium', price: 499, duration: 90, rzpPlanId: '', googlePlayId: '', googlePlaySubId: '' }
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
    const { settings, gpSettings, stats, adsSettings, reviewData } = window.monetizationState;

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
                    <i class="fab fa-google-play mr-2"></i> Google Play Intelligence
                </button>
            </div>

            <div id="monetizationContent">
                ${activeMonetizationTab === 'premium' ? renderPremiumContent(settings, gpSettings, stats, reviewData) :
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

function renderPremiumContent(settings, gpSettings, statsRaw, reviewData) {
    const stats = {
        grossRevenue: statsRaw.grossRevenue || 0,
        todayEarnings: statsRaw.todayEarnings || 0,
        monthlyRevenue: statsRaw.monthlyRevenue || 0,
        activePremiumUsers: statsRaw.activePremiumUsers || 0
    };

    return `
        <div class="space-y-10 animate-fade">
            <!-- Primary Revenue Cards -->
            <div class="grid grid-cols-4 gap-6">
                ${UI.card('Gross Revenue', '₹' + stats.grossRevenue.toLocaleString(), 'Lifetime Earnings', 'text-emerald-500', 'gross-revenue')}
                ${UI.card('Today Earnings', '₹' + stats.todayEarnings.toLocaleString(), '24h Performance', 'text-orange-500', 'today-earnings')}
                ${UI.card('Monthly Revenue', '₹' + stats.monthlyRevenue.toLocaleString(), 'Current Period', 'text-blue-500', 'monthly-revenue')}
                ${UI.card('Active Premium', stats.activePremiumUsers.toLocaleString(), 'Live Subscriptions', 'text-pink-500', 'active-premium')}
            </div>

            <div class="grid grid-cols-2 gap-10">
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

                    <div id="activeGatewayForm">
                        ${renderGatewayForm('razorpay', settings)}
                    </div>

                    <button onclick="savePaymentSettings('razorpay')" class="w-full py-4 bg-white/5 text-white border border-white/10 rounded-xl text-[10px] font-black uppercase hover:bg-white/10 transition">
                        Sync Razorpay Keys
                    </button>
                </div>

                <!-- Google Play Integration -->
                <div class="glass p-10 rounded-[3rem] space-y-8 border border-blue-500/10">
                    <div class="border-b border-white/5 pb-6">
                        <h3 class="text-xs font-black text-white uppercase tracking-widest">Google Play Billing</h3>
                        <p class="text-[8px] text-slate-500 mt-1 uppercase font-bold">Main Service authentication</p>
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
                            <label class="text-[9px] font-black text-blue-500 uppercase tracking-widest ml-1">Service Account Key (JSON)</label>
                            <textarea id="gp_service_key" rows="12" placeholder='{ "type": "service_account", ... }' class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-slate-400 font-mono mt-2">${gpSettings.serviceAccountKey || ''}</textarea>
                        </div>
                        <button onclick="saveGooglePlaySettings()" class="w-full py-4 bg-blue-500/10 text-blue-500 border border-blue-500/20 rounded-xl text-[10px] font-black uppercase hover:bg-blue-500 hover:text-white transition">
                            Update Google Play Config
                        </button>
                    </div>
                </div>
            </div>

            <!-- Message Trial Limit -->
            <div class="glass p-10 rounded-[3rem] border border-orange-500/10 flex flex-col justify-center">
                <div class="flex items-center space-x-3 mb-6">
                    <div class="p-3 bg-orange-500/10 rounded-2xl">
                        <i class="fas fa-comment-alt-dots text-orange-500 text-xl"></i>
                    </div>
                    <h3 class="text-sm font-black text-white uppercase tracking-widest">Message Trial Limit (CORE CONFIG)</h3>
                </div>

                <div class="bg-black/20 p-8 rounded-[2rem] border border-white/5 space-y-6">
                    <div class="flex items-center justify-between">
                        <p class="text-[11px] font-black text-white uppercase tracking-widest">Enable Message Limit</p>
                        <label class="relative inline-flex items-center cursor-pointer scale-125">
                            <input type="checkbox" id="one_message_trial_toggle" ${reviewData?.isOneMessageTrialEnabled ? 'checked' : ''} onchange="toggleOneMessageTrial(this)" class="sr-only peer">
                            <div class="w-12 h-6 bg-white/10 rounded-full peer peer-checked:bg-orange-500 after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:after:translate-x-6"></div>
                        </label>
                    </div>

                    <div class="pt-6 border-t border-white/5">
                        <label class="text-[9px] font-black text-slate-500 uppercase tracking-widest ml-1">Free Message Limit Count</label>
                        <div class="flex items-center space-x-4 mt-2">
                            <input type="number" id="free_message_limit" value="${reviewData?.freeMessageLimit || 1}" class="w-20 bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-sm text-white font-bold focus:border-orange-500/50">
                            <span class="text-[10px] text-slate-500 font-bold uppercase italic">Messages per user</span>
                        </div>
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

function renderGatewayForm(active, settings) {
    if (active === 'razorpay') {
        const r = settings.razorpay || {};
        return `
            <div class="flex flex-col space-y-6 pt-4">
                <div class="grid grid-cols-2 gap-4">
                    <input type="text" id="rp_key_id" value="${r.keyId || ''}" placeholder="Key ID" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-white">
                    <input type="password" id="rp_key_secret" value="${r.keySecret || ''}" placeholder="Key Secret" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-white">
                </div>
                <input type="password" id="rp_webhook_secret" value="${r.webhookSecret || ''}" placeholder="Webhook Secret" class="w-full bg-white/5 border border-white/10 p-4 rounded-xl outline-none text-[10px] text-white">
            </div>
        `;
    }
    return `<p class="text-xs text-slate-500 text-center py-10 uppercase font-bold italic opacity-30">${active} details detail soon</p>`;
}

async function savePaymentSettings(activeGateway) {
    try {
        const data = await API.getConfig('payment_settings');
        const settings = data.config || { activeGateway: 'razorpay' };

        settings.isUpiEnabled = document.getElementById('upi_toggle').checked;

        if (activeGateway === 'razorpay') {
            settings.razorpay = {
                ...settings.razorpay,
                keyId: document.getElementById('rp_key_id').value.trim(),
                keySecret: document.getElementById('rp_key_secret').value.trim(),
                webhookSecret: document.getElementById('rp_webhook_secret').value.trim()
            };
        }
        settings.activeGateway = activeGateway;
        await API.updateConfig('payment_settings', settings);
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});
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
            serviceAccountKey: document.getElementById('gp_service_key').value
        };
        await API.updateConfig('google_play_settings', config);
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});
        showSystemToast("Google Play Updated", "Configuration saved", 'bg-blue-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "Update failed", 'bg-red-500');
    }
}

async function toggleOneMessageTrial(el) {
    try {
        const reviewData = await API.getConfig('review_mode_config').catch(e => ({ success: false, config: {} }));
        const config = reviewData.config || {};
        config.isOneMessageTrialEnabled = el.checked;
        config.freeMessageLimit = parseInt(document.getElementById('free_message_limit').value) || 1;

        await API.updateConfig('review_mode_config', config);
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});
        showSystemToast("Trial Config Updated", "Settings saved", 'bg-orange-500');
        loadMonetization();
    } catch (e) {
        el.checked = !el.checked;
        showSystemToast("Sync Error", "Server not responding", 'bg-red-500');
    }
}

function switchMonetizationTab(tab) {
    activeMonetizationTab = tab;
    renderMonetizationUI();
}

async function loadPaymentHistory(page = 1, search = '') {
    const container = document.getElementById('historyTable');
    if (!container) return;

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
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});
        showSystemToast("Ads Synced", `${activeAdProvider.toUpperCase()} config broadcasted to app`, 'bg-orange-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "API communication error", 'bg-red-500');
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
                            <h3 class="text-sm font-black text-white uppercase tracking-widest">Premium Plan Configuration</h3>
                            <p class="text-[10px] text-slate-500 uppercase font-bold mt-1">Configure pricing and IDs for app plans</p>
                        </div>
                    </div>
                    <button onclick="saveOffersSettings()" class="px-8 py-3 bg-pink-500 text-white rounded-xl text-[10px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-pink-500/30">
                        <i class="fas fa-save mr-2"></i> Sync All Plans
                    </button>
                </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
                ${offers.map((offer, idx) => `
                    <div class="glass p-8 rounded-[2.5rem] border border-white/5 space-y-6">
                        <div class="flex justify-between items-center">
                             <span class="px-3 py-1 bg-white/5 rounded-full text-[8px] font-black text-slate-500 uppercase tracking-widest">Plan #${idx + 1}</span>
                             <i class="fas fa-bolt text-pink-500"></i>
                        </div>

                        <div class="space-y-4">
                            <div>
                                <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Plan Name</label>
                                <input type="text" id="offer_name_${idx}" value="${offer.name}" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[11px] text-white mt-1">
                            </div>
                            <div class="grid grid-cols-2 gap-4">
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Price (₹)</label>
                                    <input type="number" id="offer_price_${idx}" value="${offer.price}" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[11px] text-emerald-500 font-bold mt-1">
                                </div>
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Days (Duration)</label>
                                    <input type="number" id="offer_days_${idx}" value="${offer.duration}" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[11px] text-white mt-1">
                                </div>
                            </div>

                            <div class="pt-4 border-t border-white/5 space-y-4">
                                <h4 class="text-[9px] font-black text-orange-500 uppercase tracking-widest mb-2">Razorpay (UPI)</h4>
                                <div>
                                    <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Razorpay Plan ID</label>
                                    <input type="text" id="offer_rzp_id_${idx}" value="${offer.rzpPlanId || ''}" placeholder="plan_xxx" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[10px] text-orange-400 mt-1">
                                </div>
                            </div>

                            <div class="pt-4 border-t border-white/5 space-y-4">
                                <h4 class="text-[9px] font-black text-blue-500 uppercase tracking-widest mb-2">Google Play (App)</h4>
                                <div class="grid grid-cols-1 gap-3">
                                    <div>
                                        <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Product ID</label>
                                        <input type="text" id="offer_gp_sub_id_${idx}" value="${offer.googlePlaySubId || ''}" placeholder="gogo_monthly_199" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[10px] text-blue-400 mt-1">
                                    </div>
                                    <div>
                                        <label class="text-[8px] font-black text-slate-500 uppercase tracking-widest ml-1">Base/Offer ID</label>
                                        <input type="text" id="offer_gp_id_${idx}" value="${offer.googlePlayId || ''}" placeholder="gogo-19-rs-offer" class="w-full bg-white/5 border border-white/10 p-3 rounded-xl outline-none text-[10px] text-emerald-400 mt-1">
                                    </div>
                                </div>
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
                id: i === 0 ? 'weekly' : (i === 1 ? 'monthly' : 'quarterly'),
                name: document.getElementById(`offer_name_${i}`).value,
                price: parseInt(document.getElementById(`offer_price_${i}`).value) || 0,
                duration: parseInt(document.getElementById(`offer_days_${i}`).value) || 0,
                rzpPlanId: document.getElementById(`offer_rzp_id_${i}`).value,
                googlePlaySubId: document.getElementById(`offer_gp_sub_id_${i}`).value,
                googlePlayId: document.getElementById(`offer_gp_id_${i}`).value
            });
        }

        await API.updateConfig('special_offers', { offers });
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});
        showSystemToast("Plans Updated", "Plan configurations broadcasted to app", 'bg-pink-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "API communication error", 'bg-red-500');
    }
}

function renderGooglePlayDashboard() {
    return `
        <div class="space-y-10 animate-fade">
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
                <button onclick="loadGooglePlayData(1, true)" class="p-4 bg-white/5 hover:bg-white/10 rounded-2xl text-white transition shadow-xl active:rotate-180">
                    <i class="fas fa-sync-alt"></i>
                </button>
            </div>

            <!-- Primary Revenue Cards -->
            <div id="gp_summary_cards" class="grid grid-cols-5 gap-6">
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
            </div>

            <!-- Ledger Table -->
            <div class="glass rounded-[3rem] overflow-hidden">
                <div class="p-8 border-b border-white/5 bg-white/5 flex justify-between items-center">
                     <h3 class="text-xs font-black text-white uppercase tracking-widest">Google Play Transaction Ledger</h3>
                </div>
                <div id="gp_user_table">
                    ${UI.skeletonTable(10)}
                </div>
                <div id="gp_pagination"></div>
            </div>
        </div>
    `;
}

async function loadGooglePlayData(page = 1, sync = false) {
    const container = document.getElementById('gp_summary_cards');
    if (!container) return;

    try {
        let url = `/api/admin/monetization/google-play-dashboard?page=${page}&limit=20`;
        if (sync) url += '&sync=true';

        const data = await API.request(url);
        const { summary, users, pagination } = data;

        // Update Summary Cards
        document.getElementById('gp_summary_cards').innerHTML = `
            ${UI.card('Gross Revenue', '₹' + summary.lifetimeEarnings.toLocaleString(), 'Lifetime Earnings', 'text-emerald-500')}
            ${UI.card('Today Earnings', '₹' + summary.todayEarnings.toLocaleString(), '24h Live (Total)', 'text-orange-500')}
            ${UI.card('Active Premium', summary.activePremium.toLocaleString(), 'Live Subscriptions', 'text-blue-500')}
            ${UI.card('Active Mandate', summary.activeMandates.toLocaleString(), 'Auto-Renew Enabled', 'text-pink-500')}
            ${UI.card('Grace Period', summary.gracePeriod.toLocaleString(), 'In Recovery Window', 'text-yellow-500')}
        `;

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
                </td>
                <td class="p-6 text-[9px] text-slate-400 font-medium">${u.subscription?.nextBillingDate ? window.formatDateTime(u.subscription.nextBillingDate) : 'N/A'}</td>
                <td class="p-6">
                    <div class="flex items-center space-x-2">
                         ${UI.badge(u.subscription?.status || 'N/A', u.subscription?.status === 'active' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}
                    </div>
                </td>
                <td class="p-6 text-right">
                    <button onclick="viewGPUserLive('${u.phone}')" class="px-4 py-2 bg-white/5 rounded-xl text-[9px] font-black uppercase hover:bg-orange-500 hover:text-white transition-all">View</button>
                </td>
            </tr>
        `);
        document.getElementById('gp_user_table').innerHTML = UI.table(['User', 'Lifetime', 'Current', 'Purchased At', 'Next Bill', 'Status', 'Action'], rows);

        renderGPPagination(pagination);

    } catch (err) {
        console.error("GP Load Error:", err);
    }
}

function renderGPPagination(pagination) {
    const { page, pages, total } = pagination;
    const container = document.getElementById('gp_pagination');
    if (!container || pages <= 1) return;

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
    UI.modal.show('Live Intelligence', UI.skeletonModal());
    try {
        const [userData, res] = await Promise.all([
            API.getUserFull(phone),
            API.post('/payment/sync-provider', { phone })
        ]);
        const u = res.success ? res.user : userData.user;
        const sub = u.subscription || {};
        UI.modal.show(`Intelligence: ${u.name}`, `
            <div class="space-y-6 p-4">
                <div class="p-6 bg-white/5 rounded-3xl border border-white/5">
                    <h4 class="text-lg font-black text-white">${u.name}</h4>
                    <p class="text-xl font-black text-emerald-500 mt-2">₹${sub.totalAmountPaid || 0} Total Paid</p>
                </div>
                <div class="grid grid-cols-2 gap-4">
                    <div class="glass p-4 rounded-2xl border border-white/5">
                        <p class="text-[8px] font-black text-slate-500 uppercase">Status</p>
                        <p class="text-xs font-black text-white mt-1">${sub.status || 'NONE'}</p>
                    </div>
                    <div class="glass p-4 rounded-2xl border border-white/5">
                        <p class="text-[8px] font-black text-slate-500 uppercase">Next Bill</p>
                        <p class="text-xs font-black text-white mt-1">${sub.nextBillingDate ? window.formatDateTime(sub.nextBillingDate) : 'N/A'}</p>
                    </div>
                </div>
            </div>
        `);
    } catch (e) {
        UI.modal.show('Error', 'Failed to fetch data');
    }
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
        await API.post('/payment/broadcast-status-change', {}).catch(e => {});

        showSystemToast("Pricing Saved", "Strategy updated", 'bg-emerald-500');
        loadMonetization();
    } catch (err) {
        showSystemToast("Save Failed", "API error", 'bg-red-500');
    }
}
