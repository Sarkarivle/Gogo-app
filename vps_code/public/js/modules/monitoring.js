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

        // Start real event stream handler
        window.activeEventStream = true;
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing telemetry data</p>`;
    }
}

function updateMonitoringRealtime(data) {
    // Update top cards
    updateCardValue('active-sockets', data.activeSockets);
    updateCardValue('online-users', data.onlineUsers);
    updateCardValue('reconnects-(24h)', data.reconnects24h);
    updateCardValue('throughput', data.eventThroughput);

    // Update Health Bars
    const cpuVal = data.serverHealth.cpuUsage;
    const ramPercent = (((data.serverHealth.totalMem - data.serverHealth.freeMem) / data.serverHealth.totalMem) * 100).toFixed(1);

    updateHealthBar('CPU LOAD', cpuVal);
    updateHealthBar('RAM USAGE', ramPercent);

    // Update Uptime and Memory Free
    const uptimeEl = document.querySelector('p:contains("Uptime") + p'); // This might need a better selector
    // Actually let's just find by text content for now or add IDs if possible
    // To keep it simple and safe:
    document.querySelectorAll('.glass .grid p').forEach(p => {
        if (p.innerText === 'UPTIME') p.nextElementSibling.innerText = `${data.serverHealth.uptime} Hours`;
        if (p.innerText === 'MEMORY FREE') p.nextElementSibling.innerText = `${data.serverHealth.freeMem} GB`;
    });
}

function updateCardValue(id, val) {
    const el = document.querySelector(`[data-card-id="${id}"] h2`);
    if (el) el.innerText = val.toLocaleString();
}

function updateHealthBar(label, value) {
    const bars = document.querySelectorAll('.glass h3 + div > div');
    bars.forEach(bar => {
        const labelEl = bar.querySelector('span');
        if (labelEl && labelEl.innerText === label) {
            bar.querySelector('span.text-white').innerText = `${value}%`;
            bar.querySelector('.transition-all').style.width = `${value}%`;
        }
    });
}

function startEventStream() {
    // We'll hook into the real socket events instead of a mock interval
    socket.on('receive_message', (msg) => appendStreamEvent('MSG_SENT', msg.senderPhone));
    socket.on('user_status_change', (data) => appendStreamEvent(data.isOnline ? 'AUTH_SUCCESS' : 'DISCONNECT', data.phone));
}

function appendStreamEvent(type, phone) {
    const stream = document.getElementById('eventStream');
    if (!stream) return;

    const div = document.createElement('div');
    div.className = 'text-slate-400 animate-fade';
    const obscuredPhone = phone ? phone.replace(/(\d{3})\d{4}(\d{3})/, '$1****$2') : 'Internal';
    div.innerHTML = `<span class="text-[8px] opacity-30">${new Date().toLocaleTimeString()}</span> <span class="text-orange-500">[${type}]</span> Processed event for ${obscuredPhone}`;
    stream.prepend(div);
    if (stream.children.length > 50) stream.lastChild.remove();
}

async function loadServerHealth() {
    await loadMonitoring();
}
