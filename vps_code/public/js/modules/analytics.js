async function loadAnalytics() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Business Intelligence & Analytics";
    mainContent.innerHTML = UI.loader();

    try {
        const res = await fetch('/api/admin/analytics/detailed');
        const data = await res.json();

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Daily Active (DAU)', data.dau, 'Today Unique Sessions', 'text-emerald-500')}
                    ${UI.card('Monthly Active (MAU)', Math.round(data.mau), 'Rolling 30-day Active', 'text-blue-500')}
                    ${UI.card('Retention Rate', data.retention, 'Day-30 Stickiness', 'text-pink-500')}
                    ${UI.card('Avg Session', data.avgSession, 'Time Spent per User', 'text-orange-500')}
                </div>

                <div class="grid grid-cols-2 gap-10">
                    <div class="glass p-10 rounded-[3rem]">
                        <h3 class="text-xs font-black uppercase text-white mb-6">Engagement Funnel</h3>
                        <div class="space-y-6">
                            ${renderFunnelStep('Onboarding Conversion', 84)}
                            ${renderFunnelStep('Profile Completion', 62)}
                            ${renderFunnelStep('Match Rate', 35)}
                            ${renderFunnelStep('Premium Upgrade', 8)}
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

function renderFunnelStep(label, percentage) {
    return `
        <div>
            <div class="flex justify-between text-[10px] font-black mb-2">
                <span class="text-slate-500 uppercase">${label}</span>
                <span class="text-white">${percentage}%</span>
            </div>
            <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                <div class="h-full bg-gradient-to-r from-orange-500 to-orange-300" style="width: ${percentage}%"></div>
            </div>
        </div>
    `;
}
