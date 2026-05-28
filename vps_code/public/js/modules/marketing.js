async function loadMarketing() {
    console.log("🎯 Loading Marketing Management...");
    const modTitle = document.getElementById('modTitle');
    if (modTitle) modTitle.innerText = "Marketing Track";

    try {
        await MarketingModule.render();
    } catch (e) {
        console.error("❌ MarketingModule render Failed:", e);
        throw e;
    }
}

const MarketingModule = {
    render: async function() {
        const main = document.getElementById('mainContent');
        if (!main) return;
        main.innerHTML = UI.skeleton(4);

        try {
            const res = await API.get('/admin/marketing/config');
            if (res.success) {
                this.renderUI(res.config);
            }
        } catch (err) {
            UI.toast('Failed to load marketing config', 'error');
        }
    },

    renderUI: function(config) {
        const main = document.getElementById('mainContent');
        main.innerHTML = `
            <div class="animate-fade space-y-8">
                <div class="flex justify-between items-center">
                    <div>
                        <h2 class="text-3xl font-black text-white">Marketing Track</h2>
                        <p class="text-slate-500 text-sm">Manage Pixel IDs, S2S Postbacks, and Campaign Tracking</p>
                    </div>
                    <button onclick="MarketingModule.save()" class="bg-orange-500 hover:bg-orange-600 text-black font-bold px-8 py-3 rounded-xl transition shadow-lg shadow-orange-500/20">
                        SAVE ALL CHANGES
                    </button>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
                    <!-- PIXEL IDS -->
                    <div class="glass p-8 rounded-[2rem] space-y-6">
                        <div class="flex items-center space-x-3 mb-4">
                            <i class="fas fa-code text-orange-500 text-xl"></i>
                            <h3 class="text-xl font-bold text-white">Pixel & Tracking IDs</h3>
                        </div>

                        <div>
                            <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Facebook Pixel ID</label>
                            <input type="text" id="fbPixelId" value="${config.fbPixelId || ''}" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:border-orange-500 outline-none" placeholder="e.g. 1234567890">
                        </div>

                        <div>
                            <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Google Ads Conversion ID</label>
                            <input type="text" id="googleAdsId" value="${config.googleAdsId || ''}" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:border-orange-500 outline-none" placeholder="e.g. AW-123456789">
                        </div>

                        <div>
                            <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">TikTok Pixel ID</label>
                            <input type="text" id="tiktokPixelId" value="${config.tiktokPixelId || ''}" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:border-orange-500 outline-none" placeholder="e.g. C1234567890">
                        </div>
                    </div>

                    <!-- S2S POSTBACKS -->
                    <div class="glass p-8 rounded-[2rem] space-y-6">
                        <div class="flex items-center space-x-3 mb-4">
                            <i class="fas fa-network-wired text-blue-500 text-xl"></i>
                            <h3 class="text-xl font-bold text-white">S2S Postback URLs (TrafficStar etc.)</h3>
                        </div>

                        <div>
                            <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Install Postback</label>
                            <input type="text" id="installPostbackUrl" value="${config.installPostbackUrl || ''}" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:border-blue-500 outline-none" placeholder="https://trafficstar.com/postback?id={clickid}">
                        </div>

                        <div>
                            <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Registration Postback</label>
                            <input type="text" id="registrationPostbackUrl" value="${config.registrationPostbackUrl || ''}" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:border-blue-500 outline-none" placeholder="https://api.track.com/reg?id={clickid}">
                        </div>

                        <div>
                            <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Purchase/Premium Postback</label>
                            <input type="text" id="purchasePostbackUrl" value="${config.purchasePostbackUrl || ''}" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:border-blue-500 outline-none" placeholder="https://api.track.com/sale?amt={value}">
                        </div>
                    </div>

                    <!-- SETTINGS & TOGGLES -->
                    <div class="glass p-8 rounded-[2rem] lg:col-span-2">
                         <div class="flex items-center space-x-3 mb-6">
                            <i class="fas fa-toggle-on text-emerald-500 text-xl"></i>
                            <h3 class="text-xl font-bold text-white">Global Tracking Toggles</h3>
                        </div>

                        <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
                            <div class="flex items-center justify-between p-6 bg-white/5 rounded-2xl">
                                <div>
                                    <p class="font-bold text-white">Enable Global Tracking</p>
                                    <p class="text-xs text-slate-500">Master switch for all GTM/Analytics events</p>
                                </div>
                                <input type="checkbox" id="isTrackingEnabled" ${config.isTrackingEnabled ? 'checked' : ''} class="w-6 h-6 accent-orange-500">
                            </div>

                            <div class="flex items-center justify-between p-6 bg-white/5 rounded-2xl">
                                <div>
                                    <p class="font-bold text-white">Log User IP</p>
                                    <p class="text-xs text-slate-500">Send User IP to third party networks (GDPR Caution)</p>
                                </div>
                                <input type="checkbox" id="logUserIp" ${config.logUserIp ? 'checked' : ''} class="w-6 h-6 accent-orange-500">
                            </div>
                        </div>
                    </div>
                </div>

                <div class="glass p-8 rounded-[2rem] border-orange-500/20">
                    <h4 class="text-orange-500 font-bold mb-2 uppercase text-xs tracking-widest">How it works</h4>
                    <p class="text-slate-400 text-sm leading-relaxed">
                        Data entered here is synced with the mobile app in real-time. When a user triggers an event (like a call or registration), the app uses these IDs to fire GTM tags. S2S Postbacks are handled by the server whenever a conversion event is confirmed.
                    </p>
                </div>
            </div>
        `;
    },

    save: async function() {
        const data = {
            fbPixelId: document.getElementById('fbPixelId').value,
            googleAdsId: document.getElementById('googleAdsId').value,
            tiktokPixelId: document.getElementById('tiktokPixelId').value,
            installPostbackUrl: document.getElementById('installPostbackUrl').value,
            registrationPostbackUrl: document.getElementById('registrationPostbackUrl').value,
            purchasePostbackUrl: document.getElementById('purchasePostbackUrl').value,
            isTrackingEnabled: document.getElementById('isTrackingEnabled').checked,
            logUserIp: document.getElementById('logUserIp').checked
        };

        try {
            const res = await API.post('/admin/marketing/config', data);
            if (res.success) {
                UI.toast('Marketing configurations updated successfully!');
            }
        } catch (err) {
            UI.toast('Failed to update configuration', 'error');
        }
    }
};
