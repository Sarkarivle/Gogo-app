// Placeholder modules for extended features

async function loadNotifications() {
    const mainContent = document.getElementById('mainContent');
    document.getElementById('modTitle').innerText = "Campaign Manager";

    mainContent.innerHTML = `
        <div class="space-y-8 animate-fade">
            <div class="max-w-4xl mx-auto glass p-10 rounded-[3rem] space-y-8">
                <div class="border-b border-white/5 pb-6 flex justify-between items-center">
                    <div>
                        <h3 class="text-xl font-black text-white uppercase">Broadcast Center</h3>
                        <p class="text-xs text-slate-500 mt-1 uppercase font-bold">Targeted Push Notifications</p>
                    </div>
                    <div class="flex items-center space-x-4">
                        <label class="flex items-center space-x-2 cursor-pointer">
                            <input type="checkbox" id="targetPremium" checked class="w-4 h-4 accent-orange-500">
                            <span class="text-[10px] font-black uppercase text-orange-400">Premium</span>
                        </label>
                        <label class="flex items-center space-x-2 cursor-pointer">
                            <input type="checkbox" id="targetFree" checked class="w-4 h-4 accent-orange-500">
                            <span class="text-[10px] font-black uppercase text-slate-400">Free</span>
                        </label>
                        <label class="flex items-center space-x-2 cursor-pointer">
                            <input type="checkbox" id="targetUnregistered" checked class="w-4 h-4 accent-orange-500">
                            <span class="text-[10px] font-black uppercase text-blue-400">Unregistered</span>
                        </label>
                    </div>
                </div>

                <div class="space-y-4">
                    <input type="text" id="notifTitle" placeholder="Notification Title..." class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm focus:border-orange-500">
                    <textarea id="notifBody" placeholder="Message content..." class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm h-32 focus:border-orange-500"></textarea>

                    <div class="flex items-center space-x-4 p-4 glass rounded-2xl bg-white/5">
                        <i class="fas fa-clock text-slate-500"></i>
                        <span class="text-[10px] font-black uppercase text-slate-500 mr-2">Schedule For:</span>
                        <input type="datetime-local" id="scheduleAt" class="bg-transparent text-white text-xs outline-none cursor-pointer">
                        <button onclick="document.getElementById('scheduleAt').value = ''" class="text-[10px] font-black uppercase text-red-500 ml-auto">Clear</button>
                    </div>

                    <div class="flex space-x-4 pt-4">
                        <button onclick="sendBroadcast()" class="flex-1 py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase hover:scale-105 transition shadow-lg shadow-orange-500/20 font-black">Execute Broadcast</button>
                    </div>
                </div>
            </div>

            <!-- Campaign Analytics Table -->
            <div class="glass p-10 rounded-[3rem] space-y-6">
                <div class="flex justify-between items-center">
                    <h4 class="text-xs font-black text-white uppercase tracking-widest">Campaign Analytics & History</h4>
                    <span class="text-[9px] font-black text-slate-500 uppercase">Track uninstalls via FCM Failures</span>
                </div>
                <div id="campaignHistoryContainer">
                    ${UI.skeletonTable(3)}
                </div>
            </div>
        </div>
    `;

    renderCampaignHistory();
}

async function renderCampaignHistory() {
    try {
        const res = await API.getCampaigns();
        const campaigns = res.campaigns || [];

        const headers = ['Serial/ID', 'Message', 'Audience', 'Total Sent', 'Delivered', 'FCM/Failed (Uninstall)', 'Status', 'Executed At'];
        const rows = campaigns.map((c, i) => `
            <tr class="border-b border-white/5 hover:bg-white/[0.02] transition">
                <td class="p-6 text-[10px] font-black text-slate-500">#${i + 1}</td>
                <td class="p-6">
                    <p class="text-xs font-bold text-white">${c.title || 'No Title'}</p>
                    <p class="text-[10px] text-slate-500 truncate max-w-xs">${c.message}</p>
                </td>
                <td class="p-6">
                    <div class="flex flex-wrap gap-1">
                        ${c.targetAudience.map(t => `<span class="px-2 py-0.5 rounded-full text-[8px] font-black uppercase bg-white/5 text-slate-400">${t}</span>`).join('')}
                    </div>
                </td>
                <td class="p-6 text-xs font-bold text-white">${c.totalSent.toLocaleString()}</td>
                <td class="p-6 text-xs font-bold text-emerald-500">${c.totalDelivered.toLocaleString()}</td>
                <td class="p-6 text-xs font-bold text-red-500">${c.totalFailed.toLocaleString()}</td>
                <td class="p-6">
                    ${UI.badge(c.status, c.status === 'Sent' ? 'bg-emerald-500/10 text-emerald-500' : (c.status === 'Scheduled' ? 'bg-blue-500/10 text-blue-500' : 'bg-red-500/10 text-red-500'))}
                </td>
                <td class="p-6 text-[10px] text-slate-500 font-bold uppercase">${new Date(c.executedAt || c.scheduledAt).toLocaleString()}</td>
            </tr>
        `);

        document.getElementById('campaignHistoryContainer').innerHTML = UI.table(headers, rows);
    } catch (e) {
        document.getElementById('campaignHistoryContainer').innerHTML = `<p class="p-10 text-center text-red-500 uppercase font-black">Failed to load history</p>`;
    }
}

async function sendBroadcast() {
    const title = document.getElementById('notifTitle').value.trim();
    const msg = document.getElementById('notifBody').value.trim();
    const scheduledAt = document.getElementById('scheduleAt').value;

    const targets = [];
    if (document.getElementById('targetPremium').checked) targets.push('premium');
    if (document.getElementById('targetFree').checked) targets.push('free');
    if (document.getElementById('targetUnregistered').checked) targets.push('unregistered');

    if(!msg) {
        showSystemToast("Warning", "Message content is required", "bg-yellow-500");
        return;
    }

    if(targets.length === 0) {
        showSystemToast("Warning", "Please select at least one target audience", "bg-yellow-500");
        return;
    }

    const btn = document.querySelector('button[onclick="sendBroadcast()"]');
    const originalText = btn.innerText;

    try {
        btn.disabled = true;
        btn.innerText = scheduledAt ? "SCHEDULING..." : "TRANSMITTING...";

        showSystemToast("Campaign", scheduledAt ? "Scheduling Campaign..." : "Initializing Global Broadcast...", "bg-blue-500");

        const res = await API.broadcastNotification(title, msg, targets, scheduledAt);

        if(res.success) {
            showSystemToast("Success", res.message || `Broadcast sent to ${res.targetCount || 'all'} users`, "bg-emerald-500");
            document.getElementById('notifTitle').value = "";
            document.getElementById('notifBody').value = "";
            document.getElementById('scheduleAt').value = "";
            renderCampaignHistory();
        } else {
            throw new Error(res.message || "Broadcast failed at server");
        }
    } catch (err) {
        console.error("Broadcast UI Error:", err);
        showSystemToast("Error", err.message || "Failed to execute broadcast", "bg-red-500");
    } finally {
        btn.disabled = false;
        btn.innerText = originalText;
    }
}

async function loadModeration() {
    await loadReports();
}

async function loadDatabaseTools() {
    const mainContent = document.getElementById('mainContent');
    document.getElementById('modTitle').innerText = "Database Maintenance";
    mainContent.innerHTML = `
        <div class="grid grid-cols-3 gap-6 animate-fade">
            ${renderToolCard('Purge Stale Sessions', 'fas fa-broom', 'bg-red-500/10 text-red-500')}
            ${renderToolCard('Optimize Indexes', 'fas fa-database', 'bg-blue-500/10 text-blue-500')}
            ${renderToolCard('Cache Cleanup (Redis)', 'fas fa-bolt', 'bg-orange-500/10 text-orange-500')}
        </div>
    `;
}

function renderToolCard(name, icon, color) {
    return `
        <div class="glass p-8 rounded-[2.5rem] flex flex-col items-center space-y-4 hover:border-orange-500/30 transition cursor-pointer">
            <div class="w-16 h-16 rounded-3xl ${color} flex items-center justify-center text-2xl"><i class="${icon}"></i></div>
            <h4 class="text-xs font-black uppercase text-white">${name}</h4>
            <button class="text-[9px] font-black uppercase opacity-40 hover:opacity-100 transition">Execute Task</button>
        </div>
    `;
}

async function loadFraudMonitoring() {
    const mainContent = document.getElementById('mainContent');
    document.getElementById('modTitle').innerText = "Fraud & Abuse Detection";
    mainContent.innerHTML = `
        <div class="glass p-20 text-center rounded-[3rem] opacity-20 border-2 border-dashed border-white/10 animate-fade">
            <i class="fas fa-user-shield text-6xl mb-6"></i>
            <h3 class="text-xl font-black uppercase">Anti-Fraud Engine Active</h3>
            <p class="text-sm mt-2 uppercase font-bold">Scanning for multi-accounts and VPN usage</p>
        </div>
    `;
}
