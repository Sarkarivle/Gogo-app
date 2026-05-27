async function loadDashboard() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Command Dashboard";

    // Skeleton Loading State
    mainContent.innerHTML = `
        <div class="space-y-10">
            <div class="grid grid-cols-4 gap-6">
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
            </div>
            <div class="grid grid-cols-3 gap-6">
                <div class="glass p-8 rounded-[2.5rem] col-span-2 h-80 skeleton"></div>
                <div class="glass p-8 rounded-[2.5rem] h-80 skeleton"></div>
            </div>
        </div>
    `;

    try {
        const res = await API.getStats();
        const s = res.stats;

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <!-- Top Metrics -->
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Population', s.totalUsers.toLocaleString())}
                    ${UI.card('Live Now', s.onlineUsers.toLocaleString(), 'Active Sockets', 'text-emerald-500')}
                    ${UI.card('Premium', s.premiumUsers.toLocaleString(), 'Revenue Ready', 'text-orange-500')}
                    ${UI.card('Security Queue', s.pendingReports.toLocaleString(), 'Pending Review', s.pendingReports > 0 ? 'text-red-500' : 'text-slate-500')}
                </div>

                <!-- Secondary Metrics -->
                <div class="grid grid-cols-3 gap-6">
                    <div class="glass p-8 rounded-[2.5rem] col-span-2">
                        <div class="flex justify-between items-center mb-6">
                            <h3 class="text-xs font-black uppercase text-white">Growth Trajectory</h3>
                            <div class="flex space-x-2">
                                <span class="px-2 py-1 bg-emerald-500/10 text-emerald-500 text-[8px] font-black rounded uppercase">Live</span>
                            </div>
                        </div>
                        <div class="h-64 flex items-end space-x-2">
                            ${s.dailyGrowth.map(d => `
                                <div class="flex-1 flex flex-col items-center group">
                                    <div class="w-full bg-orange-500/10 rounded-t-xl group-hover:bg-orange-500/20 transition-all relative" style="height: ${(d.count / (Math.max(...s.dailyGrowth.map(x => x.count)) || 1)) * 100}%">
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
                                        <span class="text-white">${Math.round((s.genderRatio.male / (s.genderRatio.male + s.genderRatio.female || 1)) * 100)}%</span>
                                    </div>
                                    <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                                        <div class="h-full bg-blue-400" style="width: ${(s.genderRatio.male / (s.genderRatio.male + s.genderRatio.female || 1)) * 100}%"></div>
                                    </div>
                                </div>
                                <div>
                                    <div class="flex justify-between text-[10px] font-bold mb-2">
                                        <span class="text-pink-400">FEMALE</span>
                                        <span class="text-white">${Math.round((s.genderRatio.female / (s.genderRatio.male + s.genderRatio.female || 1)) * 100)}%</span>
                                    </div>
                                    <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                                        <div class="h-full bg-pink-400" style="width: ${(s.genderRatio.female / (s.genderRatio.male + s.genderRatio.female || 1)) * 100}%"></div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div class="pt-6 border-t border-white/5">
                            <p class="text-[10px] text-slate-500">Total System Messages</p>
                            <p class="text-2xl font-black text-white">${s.totalMessages.toLocaleString()}</p>
                        </div>
                    </div>
                </div>
            </div>
        `;
    } catch (err) {
        mainContent.innerHTML = `<div class="p-20 text-center text-red-500 font-bold uppercase tracking-widest">Failed to synchronize dashboard metrics</div>`;
    }
}

function updateDashboardRealtime(data) {
    // Dynamically update "Live Now" card
    const liveNowVal = document.querySelector('[data-card-id="live-now"] h2');
    if (liveNowVal) {
        const current = parseInt(liveNowVal.innerText.replace(/,/g, ''));
        if (current !== data.onlineUsers) {
            animateValue(liveNowVal, current, data.onlineUsers, 1000);
        }
    }

    // Update total messages if available
    if (data.totalMessages) {
        const msgVal = document.querySelector('.pt-6.border-t .text-2xl');
        if (msgVal) msgVal.innerText = data.totalMessages.toLocaleString();
    }
}

function animateValue(obj, start, end, duration) {
    let startTimestamp = null;
    const step = (timestamp) => {
        if (!startTimestamp) startTimestamp = timestamp;
        const progress = Math.min((timestamp - startTimestamp) / duration, 1);
        obj.innerHTML = Math.floor(progress * (end - start) + start).toLocaleString();
        if (progress < 1) {
            window.requestAnimationFrame(step);
        }
    };
    window.requestAnimationFrame(step);
}
