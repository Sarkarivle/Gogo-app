async function loadMonitoring() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Realtime System Monitoring";

    // Skeleton Loading State
    mainContent.innerHTML = `
        <div class="space-y-10 animate-fade">
            <div class="grid grid-cols-4 gap-6">
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
            </div>
            <div class="grid grid-cols-2 gap-10">
                <div class="glass p-10 rounded-[3rem] h-80 skeleton"></div>
                <div class="glass p-10 rounded-[3rem] h-80 skeleton"></div>
            </div>
        </div>
    `;

    try {
        const monitor = await API.getMonitoringData();

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <!-- TOP KPI ROW -->
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Active Sockets', monitor.activeSockets || 0, 'Total TCP Connections', 'text-emerald-500', 'mon-sockets')}
                    ${UI.card('Active Calls', monitor.activeCalls || 0, 'Running Rooms', 'text-pink-500', 'mon-calls')}
                    ${UI.card('Online Users', monitor.onlineUsers || 0, 'Authenticated Sessions', 'text-blue-500', 'mon-users')}
                    ${UI.card('Throughput', monitor.eventThroughput || '0.0/sec', 'Events per Second', 'text-orange-500', 'mon-throughput')}
                </div>

                <div class="grid grid-cols-2 gap-10">
                    <!-- INFRASTRUCTURE -->
                    <div class="glass p-10 rounded-[3rem] space-y-8">
                        <div class="flex justify-between items-center border-b border-white/5 pb-4">
                            <h3 class="text-xs font-black uppercase text-white">Infrastructure Health</h3>
                            <div class="flex items-center space-x-2">
                                <div class="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></div>
                                <span class="text-[8px] font-black text-emerald-500 uppercase tracking-widest">DB: CONNECTED</span>
                            </div>
                        </div>
                        <div class="space-y-8">
                            ${renderHealthBar('CPU LOAD', monitor.serverHealth.cpuUsage, '%', 'bg-orange-500')}
                            ${renderHealthBar('RAM USAGE', (((monitor.serverHealth.totalMem - monitor.serverHealth.freeMem) / monitor.serverHealth.totalMem) * 100).toFixed(1), '%', 'bg-blue-500')}
                        </div>
                        <div class="grid grid-cols-2 gap-6 pt-4">
                            <div class="p-6 bg-white/5 rounded-3xl border border-white/5">
                                <p class="text-[9px] font-black text-slate-500 uppercase tracking-widest mb-1">System Uptime</p>
                                <p id="monitor-uptime" class="text-xl font-black text-white">${monitor.serverHealth.uptime}h</p>
                            </div>
                            <div class="p-6 bg-white/5 rounded-3xl border border-white/5">
                                <p class="text-[9px] font-black text-slate-500 uppercase tracking-widest mb-1">Available Memory</p>
                                <p id="monitor-free-mem" class="text-xl font-black text-white">${monitor.serverHealth.freeMem} GB</p>
                            </div>
                        </div>
                    </div>

                    <!-- EVENT STREAM -->
                    <div class="glass p-10 rounded-[3rem] flex flex-col">
                        <div class="flex justify-between items-center mb-6">
                            <h3 class="text-xs font-black uppercase text-white">Realtime Event Stream</h3>
                            <span class="text-[8px] font-black text-slate-600 uppercase">Live Buffer</span>
                        </div>
                        <div id="eventStream" class="flex-1 h-[24rem] overflow-y-auto space-y-3 pr-4 font-mono text-[10px] custom-scrollbar">
                            <div class="text-emerald-500 flex items-center">
                                <i class="fas fa-check-circle mr-2 text-[8px]"></i>
                                <span>[SYSTEM] Monitoring channel established. Awaiting telemetry...</span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // Start real event stream handler
        window.activeMonitoringView = true;
    } catch (err) {
        console.error("Monitoring Load Error:", err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Telemetry Sync Failed: ${err.message}</p>`;
    }
}

function renderHealthBar(label, value, unit, color) {
    return `
        <div class="space-y-3">
            <div class="flex justify-between text-[10px] font-black uppercase tracking-widest">
                <span class="text-slate-500">${label}</span>
                <span class="text-white">${value}${unit}</span>
            </div>
            <div class="w-full h-1.5 bg-white/5 rounded-full overflow-hidden">
                <div class="h-full ${color} transition-all duration-1000" style="width: ${value}%"></div>
            </div>
        </div>
    `;
}

function updateMonitoringRealtime(data) {
    if (!window.activeMonitoringView) return;

    // Update top cards by their IDs
    updateCardValue('mon-sockets', data.activeSockets);
    updateCardValue('mon-calls', data.activeCalls);
    updateCardValue('mon-users', data.onlineUsers);
    updateCardValue('mon-throughput', data.eventThroughput);

    if (data.serverHealth) {
        const cpuVal = data.serverHealth.cpuUsage;
        const ramPercent = (((data.serverHealth.totalMem - data.serverHealth.freeMem) / data.serverHealth.totalMem) * 100).toFixed(1);

        updateHealthBarUI('CPU LOAD', cpuVal);
        updateHealthBarUI('RAM USAGE', ramPercent);

        const uptimeEl = document.getElementById('monitor-uptime');
        const memEl = document.getElementById('monitor-free-mem');
        if (uptimeEl) uptimeEl.innerText = `${data.serverHealth.uptime}h`;
        if (memEl) memEl.innerText = `${data.serverHealth.freeMem} GB`;
    }
}

function updateCardValue(id, val) {
    const el = document.querySelector(`[data-card-id="${id}"] h2`);
    if (el) el.innerText = typeof val === 'number' ? val.toLocaleString() : val;
}

function updateHealthBarUI(label, value) {
    const bars = document.querySelectorAll('.glass .space-y-3');
    bars.forEach(bar => {
        const l = bar.querySelector('.text-slate-500');
        if (l && l.innerText === label) {
            const v = bar.querySelector('.text-white');
            const p = bar.querySelector('.h-full');
            if (v) v.innerText = `${value}%`;
            if (p) p.style.width = `${value}%`;
        }
    });
}

function handleLiveMonitorEvent(event) {
    const stream = document.getElementById('eventStream');
    if (!stream) return;

    const div = document.createElement('div');
    div.className = 'flex items-start space-x-3 text-slate-400 animate-fade py-1 border-b border-white/[0.02] last:border-0';

    let icon = 'fa-info-circle';
    let color = 'text-blue-500';
    let text = event.label;

    switch(event.type) {
        case 'MESSAGE': icon = 'fa-paper-plane'; color = 'text-purple-500'; break;
        case 'CALL_START': icon = 'fa-phone-plus'; color = 'text-pink-500'; break;
        case 'USER_JOIN': icon = 'fa-user-plus'; color = 'text-emerald-500'; break;
        case 'USER_LEAVE': icon = 'fa-user-minus'; color = 'text-slate-500'; break;
        case 'EVENT': icon = 'fa-bolt'; color = 'text-orange-500'; break;
        case 'ADMIN_JOIN': icon = 'fa-user-shield'; color = 'text-blue-400'; text = `${event.user} logged into Admin`; break;
    }

    const time = new Date().toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
    const phoneInfo = event.phone ? `<span onclick="openUserControl('${event.phone}')" class="text-slate-600 font-bold ml-2 cursor-pointer hover:text-orange-500 hover:underline">(${event.phone.slice(-4)})</span>` : '';

    div.innerHTML = `
        <span class="text-[8px] opacity-20 mt-1">${time}</span>
        <i class="fas ${icon} ${color} mt-1 w-4 text-center"></i>
        <div class="flex-1">
            <span class="text-white font-bold">${text}</span>
            ${phoneInfo}
        </div>
    `;

    stream.prepend(div);
    if (stream.children.length > 100) stream.lastChild.remove();
}
