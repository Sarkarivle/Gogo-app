async function loadUsers(search = '') {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "User Management";
    mainContent.innerHTML = `
        <div class="space-y-6">
            <div class="flex justify-between items-center">
                <div class="relative w-96">
                    <i class="fas fa-search absolute left-5 top-1/2 -translate-y-1/2 text-slate-500"></i>
                    <input type="text" id="userSearch" value="${search}" onkeypress="if(event.key === 'Enter') loadUsers(this.value)" placeholder="Search Identity (Name or Phone)..." class="w-full bg-white/5 border border-white/5 p-4 pl-14 rounded-2xl outline-none text-sm focus:border-orange-500/50 transition">
                </div>
                <div class="flex space-x-2">
                    <button onclick="loadUsers()" class="glass p-4 rounded-2xl hover:bg-white/5 transition"><i class="fas fa-sync-alt"></i></button>
                </div>
            </div>
            <div id="userTableContainer">${UI.loader()}</div>
        </div>
    `;

    try {
        const users = await API.getUsers(search);
        const rows = users.map(u => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6">
                    <div class="flex items-center space-x-3">
                        <div class="w-10 h-10 rounded-xl bg-orange-500 flex items-center justify-center text-black font-black">
                            ${u.name ? u.name[0] : '?'}
                        </div>
                        <div>
                            <p class="text-sm font-bold text-white">${u.name || 'Incognito'}</p>
                            <p class="text-[10px] text-slate-500">${u.phone}</p>
                        </div>
                    </div>
                </td>
                <td class="p-6 text-xs font-bold text-slate-400">${u.city || 'Global'}</td>
                <td class="p-6">
                    <div class="flex items-center space-x-2">
                        <div class="w-2 h-2 rounded-full ${u.isOnline ? 'bg-emerald-500' : 'bg-slate-700'}"></div>
                        <span class="text-[10px] font-black uppercase ${u.isOnline ? 'text-emerald-500' : 'text-slate-500'}">${u.isOnline ? 'Online' : 'Offline'}</span>
                    </div>
                </td>
                <td class="p-6">
                    ${UI.badge(u.accountStatus || 'Active', u.accountStatus === 'Active' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}
                    ${u.isPremium ? UI.badge('Premium', 'bg-orange-500/10 text-orange-500 ml-1') : ''}
                </td>
                <td class="p-6 text-right">
                    <button onclick="openUserControl('${u.phone}')" class="px-6 py-2 bg-orange-500 text-black rounded-xl text-[10px] font-black uppercase transition hover:scale-105">Manage</button>
                </td>
            </tr>
        `);

        document.getElementById('userTableContainer').innerHTML = UI.table(
            ['User Identity', 'Location', 'Status', 'Account Status', 'Action'],
            rows
        );
    } catch (err) {
        document.getElementById('userTableContainer').innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error syncing user registry</p>`;
    }
}

async function openUserControl(phone) {
    UI.modal.show(
        `<div class="flex items-center space-x-4"><div class="custom-loader w-8 h-8"></div><p class="text-xs uppercase font-black">Fetching full user profile...</p></div>`,
        UI.loader()
    );

    try {
        const data = await API.getUserFull(phone);
        const u = data.user;
        const reports = data.reportsAgainst;

        UI.modal.show(
            `
            <div class="flex items-center space-x-4">
                <div class="w-12 h-12 rounded-2xl bg-orange-500 flex items-center justify-center text-black font-black text-xl">
                    ${u.name ? u.name[0] : '?'}
                </div>
                <div>
                    <h2 class="text-xl font-black text-white uppercase">${u.name || 'Anonymous'}</h2>
                    <p class="text-xs text-orange-500 font-bold">${u.phone}</p>
                </div>
            </div>
            `,
            `
            <div class="grid grid-cols-12 gap-10">
                <div class="col-span-4 space-y-6">
                    <div class="glass p-8 rounded-[2.5rem] space-y-4">
                        <h4 class="text-[10px] font-black text-slate-500 uppercase border-b border-white/5 pb-4">Account Status Control</h4>
                        <select id="statusSelect" class="w-full glass p-4 rounded-2xl text-xs font-bold bg-white/5 text-white outline-none">
                            <option value="Active" ${u.accountStatus === 'Active' ? 'selected' : ''}>ACTIVE</option>
                            <option value="Deactivated" ${u.accountStatus === 'Deactivated' ? 'selected' : ''}>DEACTIVATED (Chat Block)</option>
                            <option value="Suspended" ${u.accountStatus === 'Suspended' ? 'selected' : ''}>SUSPENDED (Login Block)</option>
                        </select>
                        <button onclick="updateUserStatus('${u.phone}')" class="w-full py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase transition hover:scale-105">Update Status</button>
                    </div>
                    <div class="glass p-8 rounded-[2.5rem] space-y-4">
                        <h4 class="text-[10px] font-black text-slate-500 uppercase mb-4">Security Incident Log (${reports.length})</h4>
                        <div class="max-h-[300px] overflow-y-auto space-y-2 pr-2">
                            ${reports.map(rep => `
                                <div class="p-4 bg-red-500/5 border border-red-500/10 rounded-2xl relative overflow-hidden">
                                    <div class="absolute top-2 right-4 text-[7px] font-black text-red-500 bg-red-500/10 px-2 py-0.5 rounded-full uppercase">${rep.reportType || 'PROFILE REPORT'}</div>
                                    <p class="text-[10px] font-black text-white uppercase">BY: ${rep.reporterName}</p>
                                    <p class="text-[9px] text-red-500 font-black uppercase mt-1">REASON: ${rep.category}</p>
                                    <p class="text-[10px] text-slate-400 mt-2 italic">"${rep.description || 'No details'}"</p>
                                    <p class="text-[7px] opacity-30 mt-2">${new Date(rep.timestamp).toLocaleString()}</p>
                                </div>
                            `).join('') || '<p class="text-center text-[10px] opacity-20 py-10">No security logs</p>'}
                        </div>
                    </div>
                </div>
                <div class="col-span-8 space-y-6 flex flex-col">
                    <div class="flex space-x-3 shrink-0">
                        <button onclick="loadUserInbox('${u.phone}')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-inbox mr-2 text-orange-500"></i> Inbox</button>
                        <button onclick="toggleVerify('${u.phone}', ${!u.isVerified})" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase hover:text-blue-400 ${u.isVerified ? 'text-blue-400' : 'text-slate-500'}"><i class="fas fa-check-circle mr-2"></i> ${u.isVerified ? 'Verified' : 'Verify Identity'}</button>
                        <button onclick="confirmUserAction('${u.phone}', 'clear')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase text-red-400/50 hover:text-red-400"><i class="fas fa-broom mr-2"></i> Clear History</button>
                        <button onclick="confirmUserAction('${u.phone}', 'delete')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase bg-red-600/10 text-red-600 hover:bg-red-600 hover:text-white transition"><i class="fas fa-trash-alt mr-2"></i> Wipe Account</button>
                    </div>
                    <div id="userControlDynamic" class="flex-1 glass rounded-[2.5rem] p-10 min-h-[400px] overflow-y-auto">
                        <div class="flex flex-col items-center justify-center h-full opacity-10">
                            <i class="fas fa-fingerprint text-6xl mb-6"></i>
                            <p class="text-xs font-black uppercase">System Logs & Interactions</p>
                        </div>
                    </div>
                </div>
            </div>
            `
        );
    } catch (err) {
        UI.modal.show('Error', `<p class="text-red-500 font-bold">Failed to load user profile</p>`);
    }
}

async function updateUserStatus(phone) {
    const status = document.getElementById('statusSelect').value;
    if (!confirm(`Confirm account status change to ${status}?`)) return;
    await API.updateUserStatus(phone, { accountStatus: status });
    alert("Status synchronized successfully");
    openUserControl(phone);
}

async function toggleVerify(phone, status) {
    await API.updateUserStatus(phone, { isVerified: status });
    openUserControl(phone);
}

async function confirmUserAction(phone, type) {
    const msg = type === 'delete' ? "DANGER: PERMANENTLY WIPE this account and all history?" : "Confirm CLEAR ALL messages for this user?";
    if (!confirm(msg)) return;

    if (type === 'delete') {
        await API.deleteAccount(phone);
        UI.modal.hide();
        loadUsers();
    } else {
        await API.clearChat(phone);
        alert("History purged");
        openUserControl(phone);
    }
}

async function loadUserInbox(phone) {
    UI.modal.setDynamicContent(UI.loader());
    try {
        const chats = await API.getUserInboxes(phone);
        const content = `
            <h3 class="text-xs font-black uppercase mb-6">Conversations Registry</h3>
            <div class="grid grid-cols-2 gap-4">
                ${chats.map(c => `
                    <div onclick="loadFullChat('${phone}', '${c.phone}')" class="p-5 bg-white/5 rounded-3xl border border-white/5 hover:border-orange-500 cursor-pointer group transition">
                        <div class="flex items-center space-x-2 mb-2">
                            <div class="w-2 h-2 rounded-full ${c.isOnline ? 'bg-emerald-500' : 'bg-slate-700'}"></div>
                            <p class="text-[10px] font-black uppercase text-white group-hover:text-orange-500">${c.name}</p>
                        </div>
                        <p class="text-[10px] text-slate-500 truncate italic">"${c.lastMsg}"</p>
                    </div>
                `).join('') || '<p class="col-span-2 text-center py-20 opacity-20 uppercase font-black">Empty Interaction Registry</p>'}
            </div>
        `;
        UI.modal.setDynamicContent(content);
    } catch (err) {
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load inbox</p>');
    }
}

async function loadFullChat(p1, p2) {
    UI.modal.setDynamicContent(UI.loader());
    try {
        const logs = await API.getChatHistory(p1, p2);
        const content = `
            <div class="flex justify-between items-center mb-6 border-b border-white/5 pb-4">
                <p class="text-[10px] font-black uppercase">System Logs: ${p1} ↔ ${p2}</p>
                <button onclick="loadUserInbox('${p1}')" class="text-orange-500 text-[10px] font-black uppercase hover:underline">Back to Inbox</button>
            </div>
            <div class="space-y-4 max-h-[500px] overflow-y-auto pr-2">
                ${logs.map(l => `
                    <div class="flex ${l.senderPhone === p1 ? 'justify-end' : 'justify-start'}">
                        <div class="max-w-[80%] p-4 rounded-2xl text-xs font-semibold ${l.senderPhone === p1 ? 'bg-orange-500 text-black rounded-tr-none' : 'bg-white/5 text-slate-300 rounded-tl-none'}">
                            ${l.message}
                            <p class="text-[8px] mt-2 opacity-30 font-black uppercase">${new Date(l.timestamp).toLocaleTimeString()}</p>
                        </div>
                    </div>
                `).join('')}
            </div>
        `;
        UI.modal.setDynamicContent(content);
        const area = document.getElementById('userControlDynamic');
        area.scrollTop = area.scrollHeight;
    } catch (err) {
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load logs</p>');
    }
}
