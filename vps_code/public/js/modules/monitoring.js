async function loadMonitoring() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Realtime System Monitoring";
    mainContent.innerHTML = UI.loader();

    try {
        const statsRes = await API.getStats();
        const monitorRes = await fetch('/api/admin/monitoring/sockets');
        const monitor = await monitorRes.json();
        const s = statsRes.stats;

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Active Sockets', monitor.activeSockets, 'Total TCP Connections', 'text-emerald-500')}
                    ${UI.card('Online Users', monitor.onlineUsers, 'Authenticated Presence', 'text-blue-500')}
                    ${UI.card('Reconnects (24h)', monitor.reconnects24h, 'Network Stability Index', 'text-yellow-500')}
                    ${UI.card('Throughput', monitor.eventThroughput, 'Events per Minute', 'text-orange-500')}
                </div>

                <div class="grid grid-cols-2 gap-10">
                    <div class="glass p-10 rounded-[3rem] space-y-6">
                        <h3 class="text-xs font-black uppercase text-white border-b border-white/5 pb-4">Infrastructure Health</h3>
                        <div class="space-y-6">
                            ${renderHealthBar('CPU LOAD', s.serverHealth.cpuUsage, '%', 'bg-orange-500')}
                            ${renderHealthBar('RAM USAGE', ((s.serverHealth.totalMem - s.serverHealth.freeMem) / s.serverHealth.totalMem * 100).toFixed(1), '%', 'bg-blue-500')}
                        </div>
                        <div class="grid grid-cols-2 gap-4 pt-4">
                            <div class="p-4 bg-white/5 rounded-2xl">
                                <p class="text-[8px] font-black text-slate-500 uppercase">Uptime</p>
                                <p class="text-lg font-black text-white">${s.serverHealth.uptime} Hours</p>
                            </div>
                            <div class="p-4 bg-white/5 rounded-2xl">
                                <p class="text-[8px] font-black text-slate-500 uppercase">Memory Free</p>
                                <p class="text-lg font-black text-white">${s.serverHealth.freeMem} GB</p>
                            </div>
                        </div>
                    </div>

                    <div class="glass p-10 rounded-[3rem]">
                        <h3 class="text-xs font-black uppercase text-white mb-6">Realtime Event Stream</h3>
                        <div id="eventStream" class="h-64 overflow-y-auto space-y-2 pr-2 font-mono text-[10px]">
                            <div class="text-emerald-500">[SYSTEM] Monitoring service synchronized...</div>
                            <div class="text-slate-500">[SOCKET] Handshake successful for node_prod_01</div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // Start mock stream
        startEventStream();
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing telemetry data</p>`;
    }
}

function renderHealthBar(label, value, unit, color) {
    return `
        <div>
            <div class="flex justify-between text-[10px] font-black mb-2">
                <span class="text-slate-500 uppercase">${label}</span>
                <span class="text-white">${value}${unit}</span>
            </div>
            <div class="w-full h-2 bg-white/5 rounded-full overflow-hidden">
                <div class="h-full ${color} transition-all duration-1000" style="width: ${value}%"></div>
            </div>
        </div>
    `;
}

function startEventStream() {
    const stream = document.getElementById('eventStream');
    if (!stream) return;
    const events = ['AUTH_SUCCESS', 'JOIN_ROOM', 'MSG_SENT', 'TYPING', 'DISCONNECT', 'HEARTBEAT'];
    const interval = setInterval(() => {
        if (!document.getElementById('eventStream')) { clearInterval(interval); return; }
        const div = document.createElement('div');
        div.className = 'text-slate-400 animate-fade';
        div.innerHTML = `<span class="text-[8px] opacity-30">${new Date().toLocaleTimeString()}</span> <span class="text-orange-500">[${events[Math.floor(Math.random() * events.length)]}]</span> Processed event for +91******${Math.floor(Math.random() * 9000 + 1000)}`;
        stream.prepend(div);
        if (stream.children.length > 50) stream.lastChild.remove();
    }, 2000);
}

async function loadServerHealth() {
    await loadMonitoring();
}
