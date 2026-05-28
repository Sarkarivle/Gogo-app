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
                    <button onclick="MarketingModule.save(this)" class="bg-orange-500 hover:bg-orange-600 text-black font-bold px-8 py-3 rounded-xl transition shadow-lg shadow-orange-500/20">
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

                        <div>
                            <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1 text-orange-500">Onboarding Video URL (YouTube)</label>
                            <input type="text" id="onboardingVideoUrl" value="${config.onboardingVideoUrl || ''}" class="w-full bg-white/5 border border-orange-500/30 rounded-2xl p-4 mt-2 text-white focus:border-orange-500 outline-none" placeholder="https://www.youtube.com/watch?v=...">
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

                    <!-- YOUTUBE EMBED CODE -->
                    <div class="glass p-8 rounded-[2rem] lg:col-span-2 border border-red-500/20 bg-red-500/5">
                         <div class="flex items-center justify-between mb-6">
                            <div class="flex items-center space-x-3">
                                <div class="w-12 h-12 bg-red-500 rounded-2xl flex items-center justify-center shadow-lg shadow-red-500/20">
                                    <i class="fab fa-youtube text-white text-2xl"></i>
                                </div>
                                <div>
                                    <h3 class="text-xl font-bold text-white">Trial Page Video Player</h3>
                                    <p class="text-slate-500 text-xs uppercase font-black tracking-widest">YouTube Embed Engine</p>
                                </div>
                            </div>
                            <button onclick="MarketingModule.save(this)" class="flex items-center space-x-2 bg-orange-500 hover:bg-orange-600 text-black font-black px-8 py-3 rounded-xl transition shadow-lg shadow-orange-500/30">
                                <i class="fas fa-sync-alt"></i>
                                <span>SYNC TO APP</span>
                            </button>
                        </div>

                        <div class="space-y-4">
                            <div class="flex items-center justify-between">
                                <label class="text-[10px] font-bold text-slate-400 uppercase tracking-widest ml-1">Paste YouTube Embed Code (Iframe)</label>
                                <span class="text-[10px] bg-red-500/20 text-red-500 px-2 py-1 rounded font-bold uppercase">Live Preview Active</span>
                            </div>
                            <textarea id="youtubeEmbedCode" rows="4" class="w-full bg-black/40 border border-white/10 rounded-2xl p-4 text-white focus:border-red-500 outline-none font-mono text-xs transition-all" placeholder='<iframe width="560" height="315" src="https://www.youtube.com/embed/XXXXXX" ...></iframe>'>${config.youtubeEmbedCode || ''}</textarea>
                            <div class="flex items-start space-x-2 text-[10px] text-slate-500 italic bg-black/20 p-3 rounded-xl border border-white/5">
                                <i class="fas fa-info-circle mt-0.5"></i>
                                <span>Note: The app will extract the Video ID from the 'src' attribute of your iframe and play it automatically in the Onboarding Trial page.</span>
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

    save: async function(btn) {
        console.log("🚀 Syncing Marketing Config...");
        const originalHtml = btn ? btn.innerHTML : '';
        if (btn) {
            btn.disabled = true;
            btn.innerHTML = '<i class="fas fa-spinner animate-spin"></i> SYNCING...';
        }

        try {
            const data = {
                fbPixelId: document.getElementById('fbPixelId').value,
                googleAdsId: document.getElementById('googleAdsId').value,
                tiktokPixelId: document.getElementById('tiktokPixelId').value,
                installPostbackUrl: document.getElementById('installPostbackUrl').value,
                registrationPostbackUrl: document.getElementById('registrationPostbackUrl').value,
                purchasePostbackUrl: document.getElementById('purchasePostbackUrl').value,
                onboardingVideoUrl: document.getElementById('onboardingVideoUrl').value,
                youtubeEmbedCode: document.getElementById('youtubeEmbedCode').value,
                isTrackingEnabled: document.getElementById('isTrackingEnabled').checked,
                logUserIp: document.getElementById('logUserIp').checked
            };

            const res = await API.post('/admin/marketing/config', data);
            if (res.success) {
                UI.toast('App Config Synced Successfully!', 'success');
            } else {
                UI.toast(res.message || 'Sync failed', 'error');
            }
        } catch (err) {
            console.error("❌ Sync Error:", err);
            UI.toast('Network error during sync', 'error');
        } finally {
            if (btn) {
                btn.disabled = false;
                btn.innerHTML = originalHtml;
            }
        }
    }
};
