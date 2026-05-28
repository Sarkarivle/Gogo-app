async function loadDashboard() {
    console.log("📈 Initializing loadDashboard...");
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');

    if (!modTitle || !mainContent) return;

    modTitle.innerText = "Command Dashboard";

    // 1. Show Skeleton immediately
    mainContent.innerHTML = `
        <div class="space-y-10">
            <div class="grid grid-cols-4 gap-6">
                ${UI.skeletonCard()} ${UI.skeletonCard()} ${UI.skeletonCard()} ${UI.skeletonCard()}
            </div>
            <div class="grid grid-cols-3 gap-6">
                <div class="glass p-8 rounded-[2.5rem] col-span-2 min-h-[300px] skeleton"></div>
                <div class="glass p-8 rounded-[2.5rem] min-h-[300px] skeleton"></div>
            </div>
        </div>
    `;

    try {
        console.log("📊 Fetching stats from API...");
        const res = await API.getStats();

        if (!res || !res.success || !res.stats) {
            throw new Error(res?.message || "Invalid response from server");
        }

        const s = res.stats;
        const dailyGrowth = s.dailyGrowth || [];
        const genderRatio = s.genderRatio || { male: 0, female: 0 };
        const totalGender = (genderRatio.male + genderRatio.female) || 1;
        const malePercent = Math.round((genderRatio.male / totalGender) * 100);
        const femalePercent = Math.round((genderRatio.female / totalGender) * 100);
        const maxGrowth = Math.max(...dailyGrowth.map(x => x.count), 1);

        // 2. Render actual data
        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Population', (s.totalUsers || 0).toLocaleString())}
                    ${UI.card('Live Now', (s.onlineUsers || 0).toLocaleString(), 'Active Sockets', 'text-emerald-500')}
                    ${UI.card('Premium', (s.premiumUsers || 0).toLocaleString(), 'Revenue Ready', 'text-orange-500')}
                    ${UI.card('Security Queue', (s.pendingReports || 0).toLocaleString(), 'Pending Review', s.pendingReports > 0 ? 'text-red-500' : 'text-slate-500')}
                </div>

                <div class="grid grid-cols-3 gap-6">
                    <div class="glass p-8 rounded-[2.5rem] col-span-2">
                        <div class="flex justify-between items-center mb-6">
                            <h3 class="text-xs font-black uppercase text-white">Growth Trajectory</h3>
                            <span class="px-2 py-1 bg-emerald-500/10 text-emerald-500 text-[8px] font-black rounded uppercase">Live</span>
                        </div>
                        <div class="h-64 flex items-end space-x-2">
                            ${dailyGrowth.map(d => `
                                <div class="flex-1 flex flex-col items-center group">
                                    <div class="w-full bg-orange-500/10 rounded-t-xl group-hover:bg-orange-500/20 transition-all relative" style="height: ${(d.count / maxGrowth) * 100}%">
                                        <div class="absolute -top-8 left-1/2 -translate-x-1/2 bg-orange-500 text-black text-[10px] font-black px-2 py-1 rounded opacity-0 group-hover:opacity-100 transition-opacity">${d.count}</div>
                                    </div>
                                    <p class="text-[9px] font-bold text-slate-500 mt-4 uppercase">${d.date}</p>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                    <div class="glass p-8 rounded-[2.5rem] flex flex-col justify-between">
                        <div>
                            <h3 class="text-xs font-black uppercase text-white mb-6">Demographics</h3>
                            <div class="space-y-4">
                                <div>
                                    <div class="flex justify-between text-[10px] font-bold mb-2">
                                        <span class="text-blue-400">MALE</span>
                                        <span class="text-white">${malePercent}%</span>
                                    </div>
                                    <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                                        <div class="h-full bg-blue-400" style="width: ${malePercent}%"></div>
                                    </div>
                                </div>
                                <div>
                                    <div class="flex justify-between text-[10px] font-bold mb-2">
                                        <span class="text-pink-400">FEMALE</span>
                                        <span class="text-white">${femalePercent}%</span>
                                    </div>
                                    <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                                        <div class="h-full bg-pink-400" style="width: ${femalePercent}%"></div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div class="pt-6 border-t border-white/5">
                            <p class="text-[10px] text-slate-500">Total System Messages</p>
                            <p class="text-2xl font-black text-white">${(s.totalMessages || 0).toLocaleString()}</p>
                        </div>
                    </div>
                </div>
            </div>
        `;
    } catch (err) {
        console.error("❌ Dashboard Error:", err);
        mainContent.innerHTML = `
            <div class="p-20 text-center space-y-4">
                <p class="text-red-500 font-bold uppercase tracking-widest text-sm">Failed to sync dashboard metrics</p>
                <p class="text-[10px] text-slate-500 uppercase font-black">${err.message}</p>
                <button onclick="loadDashboard()" class="px-8 py-3 glass rounded-2xl text-[10px] font-black uppercase hover:bg-white/5 transition border border-white/10 mt-4">Retry Synchronization</button>
            </div>
        `;
    }
}

function updateDashboardRealtime(data) {
    const liveNowVal = document.querySelector('[data-card-id="live-now"] h2');
    if (liveNowVal) {
        const current = parseInt(liveNowVal.innerText.replace(/,/g, ''));
        if (!isNaN(current) && current !== data.onlineUsers) {
            animateValue(liveNowVal, current, data.onlineUsers, 1000);
        }
    }
}

function animateValue(obj, start, end, duration) {
    let startTimestamp = null;
    const step = (timestamp) => {
        if (!startTimestamp) startTimestamp = timestamp;
        const progress = Math.min((timestamp - startTimestamp) / duration, 1);
        obj.innerHTML = Math.floor(progress * (end - start) + start).toLocaleString();
        if (progress < 1) window.requestAnimationFrame(step);
    };
    window.requestAnimationFrame(step);
}
