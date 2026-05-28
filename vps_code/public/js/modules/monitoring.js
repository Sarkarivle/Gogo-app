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
        const statsRes = await API.getStats();
        const monitor = await API.getMonitoringData();
        const s = statsRes.stats;

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <div class="grid grid-cols-4 gap-6">
                    ${UI.card('Active Sockets', monitor.activeSockets || 0, 'Total TCP Connections', 'text-emerald-500')}
                    ${UI.card('Online Users', monitor.onlineUsers || 0, 'Authenticated Presence', 'text-blue-500')}
                    ${UI.card('Reconnects (24h)', monitor.reconnects24h || 0, 'Network Stability Index', 'text-yellow-500')}
                    ${UI.card('Throughput', monitor.eventThroughput || '0/sec', 'Events per Minute', 'text-orange-500')}
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
                                <p id="monitor-uptime" class="text-lg font-black text-white">${s.serverHealth.uptime} Hours</p>
                            </div>
                            <div class="p-4 bg-white/5 rounded-2xl">
                                <p class="text-[8px] font-black text-slate-500 uppercase">Memory Free</p>
                                <p id="monitor-free-mem" class="text-lg font-black text-white">${s.serverHealth.freeMem} GB</p>
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

        // Start real event stream handler
        window.activeEventStream = true;
    } catch (err) {
        console.error("Monitoring Load Error:", err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing telemetry data: ${err.message}</p>`;
    }
}

function renderHealthBar(label, value, unit, color) {
    return `
        <div class="space-y-2">
            <div class="flex justify-between text-[10px] font-black uppercase">
                <span class="text-slate-500">${label}</span>
                <span class="text-white">${value}${unit}</span>
            </div>
            <div class="w-full h-2 bg-white/5 rounded-full overflow-hidden">
                <div class="h-full ${color} transition-all duration-1000" style="width: ${value}%"></div>
            </div>
        </div>
    `;
}

function updateMonitoringRealtime(data) {
    // Update top cards
    updateCardValue('active-sockets', data.activeSockets);
    updateCardValue('online-users', data.onlineUsers);
    updateCardValue('reconnects-(24h)', data.reconnects24h);
    updateCardValue('throughput', data.eventThroughput);

    if (data.serverHealth) {
        // Update Health Bars
        const cpuVal = data.serverHealth.cpuUsage;
        const ramPercent = (((data.serverHealth.totalMem - data.serverHealth.freeMem) / data.serverHealth.totalMem) * 100).toFixed(1);

        updateHealthBar('CPU LOAD', cpuVal);
        updateHealthBar('RAM USAGE', ramPercent);

        // Update Uptime and Memory Free using IDs
        const uptimeEl = document.getElementById('monitor-uptime');
        const memEl = document.getElementById('monitor-free-mem');
        if (uptimeEl) uptimeEl.innerText = `${data.serverHealth.uptime} Hours`;
        if (memEl) memEl.innerText = `${data.serverHealth.freeMem} GB`;
    }
}

function updateCardValue(id, val) {
    const el = document.querySelector(`[data-card-id="${id}"] h2`);
    if (el) el.innerText = typeof val === 'number' ? val.toLocaleString() : val;
}

function updateHealthBar(label, value) {
    document.querySelectorAll('.glass .space-y-2').forEach(barContainer => {
        const labelSpan = barContainer.querySelector('span.text-slate-500');
        if (labelSpan && labelSpan.innerText === label) {
            const valueSpan = barContainer.querySelector('span.text-white');
            const progress = barContainer.querySelector('.h-full');
            if (valueSpan) valueSpan.innerText = `${value}%`;
            if (progress) progress.style.width = `${value}%`;
        }
    });
}

function appendStreamEvent(type, phone) {
    const stream = document.getElementById('eventStream');
    if (!stream) return;

    const div = document.createElement('div');
    div.className = 'text-slate-400 animate-fade';
    const obscuredPhone = phone ? String(phone).replace(/(\d{3})\d{4}(\d{3})/, '$1****$2') : 'Internal';
    div.innerHTML = `<span class="text-[8px] opacity-30">${new Date().toLocaleTimeString()}</span> <span class="text-orange-500">[${type}]</span> Processed event for ${obscuredPhone}`;
    stream.prepend(div);
    if (stream.children.length > 50) stream.lastChild.remove();
}
