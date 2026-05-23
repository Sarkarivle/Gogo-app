async function loadAnalytics() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Business Intelligence & Analytics";
    mainContent.innerHTML = UI.loader();

    try {
        const res = await fetch('/api/admin/analytics/detailed');
        const data = await res.json();

        const fm = data.funnelMetrics || { onboardingConv: 0, trialConv: 0, premiumConv: 0, overallROI: 0 };
        const fr = data.funnelRaw || { app_open: 0, login_page_open: 0, trial_page_open: 0, premium_activated: 0 };

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Daily Active (DAU)', data.dau, 'Today Unique Sessions', 'text-emerald-500')}
                    ${UI.card('Premium Conversion', `${fm.overallROI}%`, 'Overall Conversion ROI', 'text-orange-500')}
                    ${UI.card('Retention Rate', data.retention, 'Day-30 Stickiness', 'text-pink-500')}
                    ${UI.card('Avg Session', data.avgSession, 'Time Spent per User', 'text-blue-500')}
                </div>

                <div class="grid grid-cols-2 gap-10">
                    <div class="glass p-10 rounded-[3rem] space-y-8">
                        <div>
                            <h3 class="text-xs font-black uppercase text-white mb-6">Onboarding & ROI Funnel</h3>
                            <div class="space-y-6">
                                ${renderFunnelStep('Login → Onboarding (Comp)', fm.onboardingConv)}
                                ${renderFunnelStep('Onboarding → Trial Page', fm.trialConv)}
                                ${renderFunnelStep('Trial → Premium Success', fm.premiumConv)}
                            </div>
                        </div>

                        <div class="pt-8 border-t border-white/5">
                            <h3 class="text-xs font-black uppercase text-slate-500 mb-6">Conversion Volume (Today)</h3>
                            <div class="grid grid-cols-2 gap-4">
                                <div class="p-6 bg-white/5 rounded-3xl relative overflow-hidden">
                                    <div class="absolute top-4 right-6 px-2 py-0.5 bg-emerald-500/10 text-emerald-500 text-[7px] font-black rounded uppercase">1 Min: <span id="min-app-open">0</span></div>
                                    <p class="text-[9px] font-black text-slate-500 uppercase">App Opens</p>
                                    <p class="text-2xl font-black text-white" id="raw-app-open">${fr.app_open}</p>
                                </div>
                                <div class="p-6 bg-white/5 rounded-3xl relative overflow-hidden">
                                    <div class="absolute top-4 right-6 px-2 py-0.5 bg-emerald-500/10 text-emerald-500 text-[7px] font-black rounded uppercase">1 Min: <span id="min-login-open">0</span></div>
                                    <p class="text-[9px] font-black text-slate-500 uppercase">Login Page</p>
                                    <p class="text-2xl font-black text-white" id="raw-login-open">${fr.login_page_open}</p>
                                </div>
                                <div class="p-6 bg-white/5 rounded-3xl relative overflow-hidden">
                                    <div class="absolute top-4 right-6 px-2 py-0.5 bg-emerald-500/10 text-emerald-500 text-[7px] font-black rounded uppercase">1 Min: <span id="min-trial-open">0</span></div>
                                    <p class="text-[9px] font-black text-slate-500 uppercase">Trial Seen</p>
                                    <p class="text-2xl font-black text-white" id="raw-trial-open">${fr.trial_page_open}</p>
                                </div>
                                <div class="p-6 bg-white/5 rounded-3xl relative overflow-hidden">
                                    <div class="absolute top-4 right-6 px-2 py-0.5 bg-orange-500/10 text-orange-500 text-[7px] font-black rounded uppercase">1 Min: <span id="min-premium-act">0</span></div>
                                    <p class="text-[9px] font-black text-slate-500 uppercase">Premium Sold</p>
                                    <p class="text-2xl font-black text-orange-500" id="raw-premium-act">${fr.premium_activated}</p>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="glass p-10 rounded-[3rem]">
                        <h3 class="text-xs font-black uppercase text-white mb-6">Activity Heatmap (Global)</h3>
                        <div class="grid grid-cols-7 gap-2 h-40">
                            ${Array.from({length: 28}).map(() => `
                                <div class="bg-orange-500/${Math.floor(Math.random() * 80 + 20)} rounded-lg hover:ring-2 ring-white/20 transition-all"></div>
                            `).join('')}
                        </div>
                        <p class="text-[9px] text-slate-500 mt-4 uppercase font-bold text-center">Peak activity detected: 9:00 PM - 12:00 AM</p>
                    </div>
                </div>
            </div>
        `;
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing analytics engine</p>`;
    }
}

function updateAnalyticsRealtime(data) {
    if (data.dau) {
        const dauEl = document.querySelector('[data-card-id="daily-active-(dau)"] h2');
        if (dauEl) dauEl.innerText = data.dau.toLocaleString();
    }

    if (data.funnel) {
        // Update raw numbers
        updateText('raw-app-open', data.funnel.app_open);
        updateText('raw-login-open', data.funnel.login_page_open);
        updateText('raw-trial-open', data.funnel.trial_page_open);
        updateText('raw-premium-act', data.funnel.premium_activated);

        // Update 1 Min Realtime stats
        if (data.minuteActivity) {
            updateText('min-app-open', data.minuteActivity.app_open);
            updateText('min-login-open', data.minuteActivity.login_page_open);
            updateText('min-trial-open', data.minuteActivity.trial_page_open);
            updateText('min-premium-act', data.minuteActivity.premium_activated);
        }

        // Update conversion cards and bars
        const appOpen = data.funnel.app_open || 0;
        const onboardingComp = data.funnel.onboarding_completed || 0;
        const trialOpen = data.funnel.trial_page_open || 0;
        const premiumAct = data.funnel.premium_activated || 0;

        const overallROI = appOpen > 0 ? ((premiumAct / appOpen) * 100).toFixed(1) : "0.0";
        const roiEl = document.querySelector('[data-card-id="premium-conversion"] h2');
        if (roiEl) roiEl.innerText = `${overallROI}%`;

        const onboardingConv = appOpen > 0 ? Math.round((onboardingComp / appOpen) * 100) : 0;
        const trialConv = onboardingComp > 0 ? Math.round((trialOpen / onboardingComp) * 100) : 0;
        const premiumConv = trialOpen > 0 ? Math.round((premiumAct / trialOpen) * 100) : 0;

        updateFunnelBar('Login → Onboarding (Comp)', onboardingConv);
        updateFunnelBar('Onboarding → Trial Page', trialConv);
        updateFunnelBar('Trial → Premium Success', premiumConv);
    }
}

function updateText(id, val) {
    const el = document.getElementById(id);
    if (el) el.innerText = val.toLocaleString();
}

function updateFunnelBar(label, percentage) {
    const bars = document.querySelectorAll('.glass h3 + div > div');
    bars.forEach(bar => {
        const labelEl = bar.querySelector('span');
        if (labelEl && labelEl.innerText === label) {
            bar.querySelector('span.text-white').innerText = `${percentage}%`;
            bar.querySelector('.h-full').style.width = `${percentage}%`;
        }
    });
}

function renderFunnelStep(label, percentage) {
    return `
        <div>
            <div class="flex justify-between text-[10px] font-black mb-2">
                <span class="text-slate-500 uppercase">${label}</span>
                <span class="text-white">${percentage}%</span>
            </div>
            <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                <div class="h-full bg-gradient-to-r from-orange-500 to-orange-300 transition-all duration-1000" style="width: ${percentage}%"></div>
            </div>
        </div>
    `;
}
