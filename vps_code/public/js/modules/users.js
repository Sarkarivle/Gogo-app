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
            <div id="userTableContainer">${UI.skeletonTable(10)}</div>
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
                            <p class="text-sm font-bold text-white">
                                ${u.name || 'Incognito'}
                                ${u.isDeactivated ? '<span class="text-[9px] text-orange-500 ml-1 uppercase font-black tracking-tighter">[Deactivated]</span>' : ''}
                            </p>
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
                    ${(() => {
                        const status = u.accountStatus || 'Active';
                        let colors = 'bg-emerald-500/10 text-emerald-500';
                        if (status === 'Deactivated') colors = 'bg-orange-500/10 text-orange-500';
                        else if (status !== 'Active') colors = 'bg-red-500/10 text-red-500';
                        return UI.badge(status, colors);
                    })()}
                    ${u.isPremium ? UI.badge('Premium', 'bg-orange-500/10 text-orange-500 ml-1') : ''}
                    ${u.isShadowBanned ? UI.badge('Shadow', 'bg-purple-500/10 text-purple-500 ml-1') : ''}
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
                        <div class="space-y-3">
                            <label class="text-[9px] font-black text-slate-500 uppercase">Main Status</label>
                            <select id="statusSelect" class="w-full glass p-4 rounded-2xl text-xs font-bold bg-white/5 text-white outline-none">
                                <option value="Active" ${u.accountStatus === 'Active' ? 'selected' : ''}>ACTIVE</option>
                                <option value="Deactivated" ${u.accountStatus === 'Deactivated' ? 'selected' : ''}>DEACTIVATED (Chat Block)</option>
                                <option value="Suspended" ${u.accountStatus === 'Suspended' ? 'selected' : ''}>SUSPENDED (Login Block)</option>
                            </select>
                            ${u.isDeactivated ? `
                                <div class="p-3 bg-orange-500/10 border border-orange-500/20 rounded-xl">
                                    <p class="text-[9px] font-black text-orange-500 uppercase">Deactivated On</p>
                                    <p class="text-[10px] text-white font-bold">${new Date(u.deactivatedAt).toLocaleString()}</p>
                                    <p class="text-[8px] text-slate-500 mt-1 italic">"${u.deactivationReason || 'User requested'}"</p>
                                </div>
                            ` : ''}
                        </div>
                        <div class="flex items-center justify-between p-4 glass rounded-2xl">
                            <span class="text-[10px] font-black text-slate-400 uppercase">Shadow Ban</span>
                            <button onclick="toggleShadowBan('${u.phone}', ${!u.isShadowBanned})" class="relative inline-flex h-5 w-10 items-center rounded-full ${u.isShadowBanned ? 'bg-purple-600' : 'bg-slate-700'}">
                                <span class="inline-block h-3 w-3 transform rounded-full bg-white ${u.isShadowBanned ? 'translate-x-6' : 'translate-x-1'} transition"></span>
                            </button>
                        </div>
                        <div class="flex items-center justify-between p-4 glass rounded-2xl">
                            <span class="text-[10px] font-black text-slate-400 uppercase">Premium Access</span>
                            <button onclick="togglePremium('${u.phone}', ${!u.isPremium})" class="relative inline-flex h-5 w-10 items-center rounded-full ${u.isPremium ? 'bg-orange-500' : 'bg-slate-700'}">
                                <span class="inline-block h-3 w-3 transform rounded-full bg-white ${u.isPremium ? 'translate-x-6' : 'translate-x-1'} transition"></span>
                            </button>
                        </div>
                        <button onclick="updateUserStatus('${u.phone}')" class="w-full py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase transition hover:scale-105">Sync Configuration</button>
                    </div>
                    <div class="glass p-8 rounded-[2.5rem] space-y-4">
                        <h4 class="text-[10px] font-black text-slate-500 uppercase border-b border-white/5 pb-4">Internal Admin Notes</h4>
                        <div id="adminNotesList" class="max-h-[200px] overflow-y-auto space-y-2 pr-2">
                            ${u.adminNotes?.map(n => `
                                <div class="p-3 bg-white/5 rounded-xl border border-white/5">
                                    <p class="text-[10px] text-slate-300 font-medium">${n.note}</p>
                                    <div class="flex justify-between mt-2 opacity-30">
                                        <span class="text-[7px] font-black uppercase">${n.adminName}</span>
                                        <span class="text-[7px] font-black uppercase">${new Date(n.timestamp).toLocaleDateString()}</span>
                                    </div>
                                </div>
                            `).join('') || '<p class="text-center text-[10px] opacity-20 py-10">No private notes</p>'}
                        </div>
                        <div class="flex space-x-2">
                            <input type="text" id="newAdminNote" placeholder="Add note..." class="flex-1 glass p-3 rounded-xl text-[10px] outline-none">
                            <button onclick="addAdminNote('${u.phone}')" class="px-4 glass rounded-xl text-[9px] font-black uppercase">Add</button>
                        </div>
                    </div>
                </div>
                <div class="col-span-8 space-y-6 flex flex-col">
                    <div class="flex space-x-3 shrink-0">
                        <button onclick="loadUserInbox('${u.phone}')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-inbox mr-2 text-orange-500"></i> Inbox</button>
                        <button onclick="loadUserFinance('${u.phone}')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-credit-card mr-2 text-emerald-500"></i> Finance</button>
                        <button onclick="loadUserMedia('${u.phone}')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-images mr-2 text-blue-500"></i> Media</button>
                        <button onclick="loadUserSecurity('${u.phone}')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-shield-alt mr-2 text-red-500"></i> Security</button>
                        <button onclick="openNotificationModal('${u.phone}')" class="flex-1 glass p-5 rounded-3xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-bell mr-2 text-yellow-500"></i> Notify</button>
                    </div>
                    <div id="userControlDynamic" class="flex-1 glass rounded-[2.5rem] p-10 min-h-[400px] overflow-y-auto relative">
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
    if (!confirm(`Confirm status synchronization?`)) return;
    await API.updateUserStatus(phone, { accountStatus: status });
    alert("Profile synchronized successfully");
    openUserControl(phone);
}

async function toggleShadowBan(phone, status) {
    await API.updateUserStatus(phone, { isShadowBanned: status });
    openUserControl(phone);
}

async function togglePremium(phone, status) {
    await API.updateUserStatus(phone, { isPremium: status });
    openUserControl(phone);
}

async function addAdminNote(phone) {
    const note = document.getElementById('newAdminNote').value;
    if(!note) return;
    await API.addAdminUserNote(phone, { note, adminName: 'Himanshu' });
    openUserControl(phone);
}

async function openNotificationModal(phone) {
    const content = `
        <div class="space-y-6 animate-fade">
            <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest border-b border-white/5 pb-2">Send Direct Push Notification</h4>
            <div class="space-y-4">
                <input type="text" id="notifTitle" placeholder="Title (e.g., Profile Update Required)" class="w-full glass p-4 rounded-2xl text-xs">
                <textarea id="notifMsg" placeholder="Message content..." class="w-full glass p-4 rounded-2xl text-xs h-32"></textarea>
                <button onclick="sendDirectNotify('${phone}')" class="w-full py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase">Send Immediately</button>
            </div>
        </div>
    `;
    UI.modal.setDynamicContent(content);
}

async function sendDirectNotify(phone) {
    const title = document.getElementById('notifTitle').value;
    const message = document.getElementById('notifMsg').value;
    await API.sendDirectUserNotify(phone, { title, message });
    alert("Notification queued for delivery");
    openUserControl(phone);
}

async function loadUserSecurity(phone) {
    UI.modal.setDynamicContent(UI.skeletonModal());
    try {
        const data = await API.getUserFull(phone);
        const u = data.user;
        const reports = data.reportsAgainst;

        const content = `
            <div class="space-y-8 animate-fade">
                <div>
                    <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-4 border-b border-white/5 pb-2">Device & Network Profile</h4>
                    <div class="grid grid-cols-2 gap-4">
                        <div class="glass p-4 rounded-2xl">
                            <p class="text-[8px] font-black text-slate-500 uppercase">Current IP Address</p>
                            <p class="text-xs font-bold text-white">${u.ipAddress || 'Unknown'}</p>
                        </div>
                        <div class="glass p-4 rounded-2xl">
                            <p class="text-[8px] font-black text-slate-500 uppercase">Hardware ID (UUID)</p>
                            <p class="text-xs font-bold text-white truncate">${u.deviceId || 'N/A'}</p>
                        </div>
                    </div>
                </div>

                <div>
                    <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-4 border-b border-white/5 pb-2">Login History (Recent Devices)</h4>
                    <div class="space-y-2">
                        ${u.deviceHistory?.map(d => `
                            <div class="flex items-center justify-between p-4 bg-white/5 rounded-2xl">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase">${d.model || 'Unknown Device'}</p>
                                    <p class="text-[8px] text-slate-500 uppercase font-bold">${d.os || 'Unknown OS'} • ${d.ip}</p>
                                </div>
                                <p class="text-[9px] text-slate-500 font-bold uppercase">${new Date(d.lastUsed).toLocaleString()}</p>
                            </div>
                        `).join('') || '<p class="text-center py-10 opacity-20 uppercase font-black text-[10px]">No login history tracked</p>'}
                    </div>
                </div>

                <div>
                    <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-4 border-b border-white/5 pb-2">Report Logs (${reports.length})</h4>
                    <div class="space-y-2">
                        ${reports.map(rep => `
                            <div class="p-4 bg-red-500/5 border border-red-500/10 rounded-2xl">
                                <div class="flex justify-between items-start mb-2">
                                    <p class="text-[10px] font-black text-white uppercase">BY: ${rep.reporterName}</p>
                                    ${UI.badge(rep.category, 'bg-red-500 text-white')}
                                </div>
                                <p class="text-[10px] text-slate-400 italic">"${rep.description || 'No details provided'}"</p>
                            </div>
                        `).join('') || '<p class="text-center py-10 opacity-20 uppercase font-black text-[10px]">No incident reports</p>'}
                    </div>
                </div>

                <!-- Danger Zone -->
                <div class="p-8 rounded-[2rem] bg-red-500/5 border border-red-500/10 space-y-4">
                    <h4 class="text-[10px] font-black text-red-500 uppercase tracking-widest text-center">Danger Zone</h4>
                    <div class="grid grid-cols-2 gap-4">
                        <button onclick="confirmUserAction('${u.phone}', 'clear')" class="py-4 glass text-red-400 rounded-2xl text-[9px] font-black uppercase hover:bg-red-500/10 transition">
                            <i class="fas fa-broom mr-2"></i> Clear Chat History
                        </button>
                        <button onclick="confirmUserAction('${u.phone}', 'delete')" class="py-4 bg-red-500/10 text-red-500 rounded-2xl text-[9px] font-black uppercase hover:bg-red-500 hover:text-white transition">
                            <i class="fas fa-trash-alt mr-2"></i> Wipe Account Data
                        </button>
                    </div>
                    <p class="text-[8px] text-red-500/50 text-center uppercase font-bold">Warning: These actions are permanent and cannot be undone.</p>
                </div>
            </div>
        `;
        UI.modal.setDynamicContent(content);
    } catch (e) { UI.modal.setDynamicContent('Error loading security data'); }
}

async function loadUserFinance(phone) {
    UI.modal.setDynamicContent(UI.skeletonModal());
    try {
        const data = await API.getUserFull(phone);
        const sub = data.subscription;
        const payments = data.paymentHistory;

        const content = `
            <div class="space-y-8 animate-fade">
                <!-- Subscription Card -->
                <div class="glass p-8 rounded-3xl bg-emerald-500/5 border border-emerald-500/10">
                    <div class="flex justify-between items-start mb-6">
                        <div>
                            <p class="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Active Subscription</p>
                            <h3 class="text-xl font-black text-white uppercase">${sub.planName || 'Free Tier'}</h3>
                        </div>
                        ${UI.badge(sub.status || 'None', sub.status === 'active' ? 'bg-emerald-500 text-black' : 'bg-slate-700 text-white')}
                    </div>
                    <div class="grid grid-cols-3 gap-6">
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase">Valid Until</p>
                            <p class="text-xs font-bold text-white">${sub.expiryDate ? new Date(sub.expiryDate).toLocaleDateString() : 'N/A'}</p>
                        </div>
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase">Total Spent</p>
                            <p class="text-xs font-bold text-emerald-500">₹${payments.reduce((acc, p) => acc + (p.amount || 0), 0)}</p>
                        </div>
                    </div>
                </div>

                <!-- Payment Logs -->
                <div>
                    <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-4 border-b border-white/5 pb-2">Transaction History</h4>
                    <div class="space-y-2">
                        ${payments.map(p => `
                            <div class="flex items-center justify-between p-4 bg-white/5 rounded-2xl border border-white/5">
                                <div>
                                    <p class="text-[10px] font-black text-white uppercase">${p.orderId || 'Direct Payment'}</p>
                                    <p class="text-[8px] text-slate-500 font-bold uppercase">${new Date(p.createdAt).toLocaleString()}</p>
                                </div>
                                <div class="text-right">
                                    <p class="text-[10px] font-black text-emerald-500 uppercase">₹${p.amount}</p>
                                    <p class="text-[8px] text-slate-500 font-bold uppercase">${p.status}</p>
                                </div>
                            </div>
                        `).join('') || '<p class="text-center py-10 opacity-20 uppercase font-black text-[10px]">No payments found</p>'}
                    </div>
                </div>
            </div>
        `;
        UI.modal.setDynamicContent(content);
    } catch (e) {
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load finance data</p>');
    }
}

async function loadUserMedia(phone) {
    UI.modal.setDynamicContent(UI.skeletonModal());
    try {
        const data = await API.getUserFull(phone);
        const u = data.user;
        const images = u.profileImages || [];

        const content = `
            <div class="space-y-6 animate-fade">
                <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest border-b border-white/5 pb-2">Media Assets (Profile)</h4>
                <div class="grid grid-cols-3 gap-4">
                    ${images.map(img => `
                        <div class="relative aspect-square rounded-2xl overflow-hidden group">
                            <img src="${img}" class="w-full h-full object-cover">
                            <div class="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition flex items-center justify-center space-x-2">
                                <button onclick="window.open('${img}')" class="w-8 h-8 glass rounded-full flex items-center justify-center text-[10px]"><i class="fas fa-expand"></i></button>
                                <button class="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center text-[10px]"><i class="fas fa-trash"></i></button>
                            </div>
                        </div>
                    `).join('') || '<p class="col-span-3 text-center py-20 opacity-20 uppercase font-black text-[10px]">No media uploaded</p>'}
                </div>
            </div>
        `;
        UI.modal.setDynamicContent(content);
    } catch (e) {
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load media assets</p>');
    }
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
    UI.modal.setDynamicContent(UI.skeletonModal());
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
    UI.modal.setDynamicContent(UI.skeletonModal());
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
