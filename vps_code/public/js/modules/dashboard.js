async function loadDashboard() {
    console.log("📈 Initializing loadDashboard...");
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');

    if (!modTitle || !mainContent) return;

    modTitle.innerText = "Command Dashboard";

    // Show Skeletons
    mainContent.innerHTML = `
        <div class="space-y-8">
            <div class="grid grid-cols-4 gap-6">
                ${UI.skeletonCard()} ${UI.skeletonCard()} ${UI.skeletonCard()} ${UI.skeletonCard()}
            </div>
            <div class="grid grid-cols-3 gap-6">
                <div class="glass p-8 rounded-[2.5rem] col-span-2 min-h-[350px] skeleton"></div>
                <div class="glass p-8 rounded-[2.5rem] min-h-[350px] skeleton"></div>
            </div>
        </div>
    `;

    try {
        const res = await API.getStats();
        if (!res || !res.success) throw new Error("Sync Failed");

        const s = res.stats;
        const r = s.revenue || {};

        const genderRatio = s.genderRatio || { male: 0, female: 0 };
        const totalGender = (genderRatio.male + genderRatio.female) || 1;
        const malePercent = Math.round((genderRatio.male / totalGender) * 100);
        const femalePercent = Math.round((genderRatio.female / totalGender) * 100);

        mainContent.innerHTML = `
            <div class="space-y-8 animate-fade">
                <!-- TOP KPI CARDS -->
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Total Population', (s.totalUsers || 0).toLocaleString(), `${s.incompleteUsers || 0} Incomplete`, 'text-slate-400')}
                    ${UI.card('Active Now', (s.onlineUsers || 0).toLocaleString(), `${s.activeCalls || 0} Live Calls`, 'text-emerald-500')}
                    ${UI.card('Monthly Revenue', `₹${(r.monthlyRevenue || 0).toLocaleString()}`, `ARPU: ₹${r.arpu || 0}`, 'text-orange-500')}
                    ${UI.card('Conversion', `${r.conversionRate || 0}%`, 'Free to Premium', 'text-blue-400')}
                </div>

                <!-- MAIN INSIGHTS ROW -->
                <div class="grid grid-cols-3 gap-6">
                    <!-- Top Cities (Placeholder for stability) -->
                    <div class="glass p-8 rounded-[2.5rem] col-span-2">
                        <div class="flex justify-between items-center mb-10">
                            <div>
                                <h3 class="text-xs font-black uppercase text-white">System Status</h3>
                                <p class="text-[10px] text-slate-500 mt-1 uppercase font-bold">Platform health & metrics</p>
                            </div>
                        </div>
                        <div class="grid grid-cols-2 gap-10">
                            <div class="space-y-6">
                                <div class="p-6 bg-emerald-500/5 border border-emerald-500/10 rounded-3xl">
                                    <p class="text-[10px] font-black text-emerald-500 uppercase mb-2">Network Health</p>
                                    <h4 class="text-xl font-black text-white">OPTIMIZED</h4>
                                    <p class="text-[8px] text-slate-500 mt-2 uppercase font-bold">All services running within normal latency.</p>
                                </div>
                                <div class="p-6 bg-blue-500/5 border border-blue-500/10 rounded-3xl">
                                    <p class="text-[10px] font-black text-blue-500 uppercase mb-2">Data Integrity</p>
                                    <h4 class="text-xl font-black text-white">VERIFIED</h4>
                                    <p class="text-[8px] text-slate-500 mt-2 uppercase font-bold">Realtime sync established with edge nodes.</p>
                                </div>
                            </div>
                            <!-- Interaction Stats -->
                            <div class="glass bg-white/5 p-8 rounded-[2rem] border border-white/5">
                                <h3 class="text-[10px] font-black uppercase text-slate-500 mb-6">Engagement Overview</h3>
                                <div class="space-y-4">
                                    <div class="flex justify-between items-center">
                                        <span class="text-[10px] font-bold text-slate-400 uppercase">Daily Active</span>
                                        <span class="text-sm font-black text-white">${(s.dau || 0).toLocaleString()}</span>
                                    </div>
                                    <div class="flex justify-between items-center">
                                        <span class="text-[10px] font-bold text-slate-400 uppercase">Retention</span>
                                        <span class="text-sm font-black text-emerald-500">${s.retention || '0%'}</span>
                                    </div>
                                    <div class="flex justify-between items-center">
                                        <span class="text-[10px] font-bold text-slate-400 uppercase">Avg Messages</span>
                                        <span class="text-sm font-black text-white">${s.avgMessagesPerUser || 0}</span>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <!-- User Funnel -->
                    <div class="glass p-8 rounded-[2.5rem] flex flex-col">
                        <h3 class="text-xs font-black uppercase text-white mb-8">User Funnel</h3>
                        <div class="flex-1 space-y-6">
                            ${renderFunnelStep('App Open', s.funnelRaw?.app_open, 100, 'bg-slate-500')}
                            ${renderFunnelStep('Onboarding', s.funnelRaw?.onboarding_completed, s.funnelMetrics?.onboardingConv, 'bg-blue-500')}
                            ${renderFunnelStep('Trial Started', s.funnelRaw?.trial_page_open, s.funnelMetrics?.trialConv, 'bg-purple-500')}
                            ${renderFunnelStep('Premium', s.funnelRaw?.premium_activated, s.funnelMetrics?.premiumConv, 'bg-orange-500')}
                        </div>
                        <div class="pt-6 mt-6 border-t border-white/5 flex justify-between items-center">
                            <span class="text-[10px] font-black text-slate-500 uppercase">Overall ROI</span>
                            <span class="text-lg font-black text-emerald-500">${s.funnelMetrics?.overallROI || 0}%</span>
                        </div>
                    </div>
                </div>

                <!-- SECONDARY STATS ROW -->
                <div class="grid grid-cols-4 gap-6">
                    <!-- Demographics -->
                    <div class="glass p-8 rounded-[2.5rem] col-span-1">
                        <h3 class="text-[10px] font-black uppercase text-slate-500 mb-6">Demographics</h3>
                        <div class="space-y-6">
                            <div>
                                <div class="flex justify-between text-[10px] font-bold mb-2">
                                    <span class="text-blue-400">MALE</span>
                                    <span class="text-white">${malePercent}%</span>
                                </div>
                                <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-blue-400" style="width: ${malePercent}%"></div></div>
                            </div>
                            <div>
                                <div class="flex justify-between text-[10px] font-bold mb-2">
                                    <span class="text-pink-400">FEMALE</span>
                                    <span class="text-white">${femalePercent}%</span>
                                </div>
                                <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden"><div class="h-full bg-pink-400" style="width: ${femalePercent}%"></div></div>
                            </div>
                        </div>
                    </div>

                    <!-- Interaction Stats -->
                    <div class="glass p-8 rounded-[2.5rem] col-span-1">
                        <h3 class="text-[10px] font-black uppercase text-slate-500 mb-6">Engagement</h3>
                        <div class="space-y-4">
                            <div class="flex justify-between items-center">
                                <span class="text-[10px] font-bold text-slate-400">Total Messages</span>
                                <span class="text-sm font-black text-white">${(s.totalMessages || 0).toLocaleString()}</span>
                            </div>
                            <div class="flex justify-between items-center">
                                <span class="text-[10px] font-bold text-slate-400">Avg Msg/User</span>
                                <span class="text-sm font-black text-white">${s.avgMessagesPerUser || 0}</span>
                            </div>
                            <div class="flex justify-between items-center">
                                <span class="text-[10px] font-bold text-slate-400">Daily Active (DAU)</span>
                                <span class="text-sm font-black text-white">${(s.dau || 0).toLocaleString()}</span>
                            </div>
                            <div class="flex justify-between items-center">
                                <span class="text-[10px] font-bold text-slate-400">Retention</span>
                                <span class="text-sm font-black text-emerald-500">${s.retention || '0%'}</span>
                            </div>
                        </div>
                    </div>

                    <!-- Recent Transactions -->
                    <div class="glass p-8 rounded-[2.5rem] col-span-2">
                        <div class="flex justify-between items-center mb-6">
                            <h3 class="text-[10px] font-black uppercase text-slate-500">Live Transactions</h3>
                            <span class="text-[9px] font-black text-orange-500 uppercase cursor-pointer hover:underline" onclick="changeModule('monetization')">View All</span>
                        </div>
                        <div class="space-y-3">
                            ${(r.recentTransactions || []).map(t => `
                                <div class="flex items-center justify-between p-3 rounded-2xl bg-white/5 border border-white/5">
                                    <div class="flex items-center space-x-3">
                                        <div class="w-8 h-8 rounded-full bg-emerald-500/20 flex items-center justify-center text-emerald-500">
                                            <i class="fas fa-arrow-down text-xs"></i>
                                        </div>
                                        <div>
                                            <p class="text-[10px] font-black text-white">+91 ${t.userPhone.slice(-10)}</p>
                                            <p class="text-[8px] text-slate-500 uppercase font-bold">${new Date(t.createdAt).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})} via ${t.gateway}</p>
                                        </div>
                                    </div>
                                    <div class="text-right">
                                        <p class="text-xs font-black text-white">₹${t.amount}</p>
                                        <p class="text-[8px] ${t.status === 'SUCCESS' ? 'text-emerald-500' : 'text-red-500'} font-black uppercase">${t.status}</p>
                                    </div>
                                </div>
                            `).join('') || '<p class="text-center py-10 text-slate-600 text-xs font-bold uppercase">No recent activity</p>'}
                        </div>
                    </div>
                </div>
            </div>
        `;

    } catch (err) {
        console.error("Dashboard Error:", err);
        mainContent.innerHTML = `<div class="p-20 text-center"><p class="text-red-500 font-bold">Failed to load system metrics. Check connection.</p></div>`;
    }
}

function renderFunnelStep(label, value, percent, colorClass) {
    return `
        <div>
            <div class="flex justify-between text-[10px] font-black mb-2">
                <span class="text-slate-400 uppercase">${label}</span>
                <span class="text-white">${(value || 0).toLocaleString()} <span class="text-slate-600 ml-1">(${percent}%)</span></span>
            </div>
            <div class="w-full h-1 bg-white/5 rounded-full overflow-hidden">
                <div class="h-full ${colorClass}" style="width: ${percent}%"></div>
            </div>
        </div>
    `;
}

function updateDashboardRealtime(data) {
    // Realtime socket updates can be handled here if needed
}
