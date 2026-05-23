async function loadPolicies() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Policy Infrastructure";
    mainContent.innerHTML = UI.loader();

    try {
        const data = await API.getPolicies();
        const types = [
            { id: 'privacy_policy', name: 'Privacy Policy' },
            { id: 'terms_conditions', name: 'Terms & Conditions' },
            { id: 'refund_policy', name: 'Refund Policy' },
            { id: 'about_us', name: 'About Us' },
            { id: 'safety_protection', name: 'Safety & Child Protection' }
        ];

        mainContent.innerHTML = `
            <div class="max-w-4xl glass p-10 rounded-[3rem] space-y-8 animate-fade mx-auto">
                <div class="border-b border-white/5 pb-6">
                    <h3 class="text-xl font-black text-white uppercase">Legal & Compliance</h3>
                    <p class="text-xs text-slate-500 mt-1 uppercase font-bold">Manage external documentation links for the mobile application</p>
                </div>
                ${types.map(t => {
                    const p = data.policies.find(x => x.type === t.id);
                    return `
                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block">${t.name}</label>
                            <div class="flex space-x-4">
                                <input type="text" id="url-${t.id}" value="${p ? p.url : ''}" placeholder="https://..." class="flex-1 bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm focus:border-orange-500/50 transition">
                                <button onclick="savePolicy('${t.id}')" class="px-8 py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase hover:scale-105 transition shadow-lg shadow-orange-500/20">Sync</button>
                            </div>
                        </div>
                    `;
                }).join('')}
            </div>
        `;
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing policy data</p>`;
    }
}

async function savePolicy(type) {
    const url = document.getElementById(`url-${type}`).value;
    try {
        await API.updatePolicy(type, url);
        alert("Policy synchronized successfully");
    } catch (err) {
        alert("Failed to update policy");
    }
}

// --- SUPPORT CENTER MODULE ---

let currentSupportFilters = {
    status: '',
    category: '',
    priority: ''
};
let cachedAdmins = [];

async function loadSupportMessages() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Support & Moderation Center";

    // Fetch admins for assignment system
    if (cachedAdmins.length === 0) {
        try { cachedAdmins = await API.getAdmins(); } catch(e) {}
    }

    mainContent.innerHTML = `
        <div class="space-y-6 animate-fade">
            <!-- Filter Bar -->
            <div class="glass p-6 rounded-[2rem] flex items-center space-x-4">
                <div class="flex-1 grid grid-cols-4 gap-4">
                    <select onchange="filterSupport('status', this.value)" class="bg-white/5 border border-white/10 rounded-xl px-4 py-2 text-xs font-bold uppercase text-slate-400 outline-none focus:border-orange-500/50">
                        <option value="">All Statuses</option>
                        <option value="Pending">Pending</option>
                        <option value="In Review">In Review</option>
                        <option value="Waiting For User">Waiting For User</option>
                        <option value="Escalated">Escalated</option>
                        <option value="Resolved">Resolved</option>
                        <option value="Closed">Closed</option>
                    </select>
                    <select onchange="filterSupport('category', this.value)" class="bg-white/5 border border-white/10 rounded-xl px-4 py-2 text-xs font-bold uppercase text-slate-400 outline-none focus:border-orange-500/50">
                        <option value="">All Categories</option>
                        <option value="Payment Issue">Payment Issue</option>
                        <option value="Child Safety">Child Safety</option>
                        <option value="Harassment">Harassment</option>
                        <option value="Account Ban">Account Ban</option>
                        <option value="Technical Bug">Technical Bug</option>
                    </select>
                    <select onchange="filterSupport('priority', this.value)" class="bg-white/5 border border-white/10 rounded-xl px-4 py-2 text-xs font-bold uppercase text-slate-400 outline-none focus:border-orange-500/50">
                        <option value="">All Priorities</option>
                        <option value="Critical">Critical</option>
                        <option value="High">High</option>
                        <option value="Medium">Medium</option>
                        <option value="Low">Low</option>
                    </select>
                    <button onclick="loadSupportMessages()" class="glass rounded-xl px-4 py-2 text-[10px] font-black uppercase hover:bg-white/10 transition">Apply Filters</button>
                </div>
            </div>

            <!-- Stats Overview -->
            <div id="supportStats" class="grid grid-cols-4 gap-6"></div>

            <!-- Tickets Table -->
            <div id="ticketsContainer" class="min-h-[400px]">
                ${UI.loader()}
            </div>
        </div>
    `;

    renderSupportList();
}

async function filterSupport(key, value) {
    currentSupportFilters[key] = value;
    renderSupportList();
}

async function renderSupportList() {
    const container = document.getElementById('ticketsContainer');
    try {
        const data = await API.getSupportMessages(currentSupportFilters);
        const messages = data.messages;

        // Update Stats (Local calc for now)
        const stats = {
            total: data.pagination.total,
            pending: messages.filter(m => m.status === 'Pending').length,
            critical: messages.filter(m => m.priority === 'Critical').length,
            resolved: messages.filter(m => m.status === 'Resolved').length
        };
        renderSupportStats(stats);

        const rows = messages.map(m => `
            <tr class="hover:bg-white/[0.01] transition group">
                <td class="p-6">
                    <div class="flex items-center space-x-3">
                        <div class="w-8 h-8 rounded-lg bg-orange-500/10 flex items-center justify-center text-orange-500 font-bold text-xs">${m.name[0]}</div>
                        <div>
                            <p class="text-xs font-black text-white">${m.name}</p>
                            <p class="text-[9px] text-slate-500 font-bold uppercase">${m.phone || m.email || 'No Contact'}</p>
                        </div>
                    </div>
                </td>
                <td class="p-6">
                    <div class="flex flex-col space-y-1">
                        <span class="text-[10px] font-black text-slate-300 uppercase">${m.category}</span>
                        <p class="text-[9px] text-slate-500 line-clamp-1 max-w-[200px]">${m.subject || m.message}</p>
                    </div>
                </td>
                <td class="p-6">
                    ${getPriorityBadge(m.priority)}
                </td>
                <td class="p-6">
                    ${getStatusBadge(m.status)}
                </td>
                <td class="p-6">
                   <p class="text-[10px] text-slate-500 font-bold uppercase">${new Date(m.createdAt).toLocaleDateString()}</p>
                   <p class="text-[9px] text-slate-600 uppercase">${new Date(m.createdAt).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</p>
                </td>
                <td class="p-6 text-right">
                    <button onclick="viewSupportMessage('${m._id}')" class="px-6 py-2 glass rounded-xl text-[9px] font-black uppercase hover:bg-orange-500 hover:text-black transition group-hover:scale-105">Interact</button>
                </td>
            </tr>
        `);

        container.innerHTML = UI.table(
            ['User', 'Ticket Information', 'Priority', 'Status', 'Timestamp', 'Action'],
            rows
        );
    } catch (err) {
        container.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing support queue</p>`;
    }
}

function renderSupportStats(stats) {
    const el = document.getElementById('supportStats');
    if (!el) return;
    el.innerHTML = `
        ${UI.card('Total Tickets', stats.total, 'Lifetime volume', 'text-white')}
        ${UI.card('Pending Queue', stats.pending, 'Awaiting first response', 'text-orange-500')}
        ${UI.card('Critical Ops', stats.critical, 'Immediate action required', 'text-red-500')}
        ${UI.card('Resolved', stats.resolved, 'Success rate: 100%', 'text-emerald-500')}
    `;
}

function getPriorityBadge(p) {
    switch(p) {
        case 'Critical': return UI.badge('Critical', 'bg-red-500 text-white shadow-lg shadow-red-500/20');
        case 'High': return UI.badge('High', 'bg-red-500/10 text-red-500');
        case 'Medium': return UI.badge('Medium', 'bg-orange-500/10 text-orange-500');
        case 'Low': return UI.badge('Low', 'bg-slate-500/10 text-slate-500');
        default: return UI.badge(p, 'bg-slate-500/10 text-slate-500');
    }
}

function getStatusBadge(s) {
    const colors = {
        'Pending': 'bg-orange-500/10 text-orange-500',
        'In Review': 'bg-blue-500/10 text-blue-500',
        'Waiting For User': 'bg-purple-500/10 text-purple-500',
        'Escalated': 'bg-red-500/10 text-red-500',
        'Resolved': 'bg-emerald-500/10 text-emerald-500',
        'Closed': 'bg-slate-500/10 text-slate-500',
        'Reopened': 'bg-orange-500 text-black'
    };
    return UI.badge(s, colors[s] || 'bg-white/5 text-white');
}

async function viewSupportMessage(id) {
    UI.modal.show('Ticket Interaction Center', UI.loader());

    try {
        const data = await API.getTicketDetail(id);
        const t = data.ticket;

        const content = `
            <div class="grid grid-cols-3 gap-10 h-full">
                <!-- Left: Ticket Content -->
                <div class="col-span-2 space-y-8 pr-10 border-r border-white/5">
                    <div class="flex justify-between items-start">
                        <div>
                            <h2 class="text-2xl font-black text-white uppercase tracking-tight">${t.subject || 'Support Ticket'}</h2>
                            <p class="text-xs text-slate-500 uppercase font-bold mt-1">Ticket ID: ${t._id}</p>
                        </div>
                        <div class="flex space-x-2">
                            ${getPriorityBadge(t.priority)}
                            ${getStatusBadge(t.status)}
                        </div>
                    </div>

                    <div class="glass p-8 rounded-3xl bg-white/[0.02]">
                        <p class="text-[10px] font-black text-slate-500 uppercase mb-4 tracking-widest">User Message</p>
                        <p class="text-sm text-slate-200 leading-relaxed">${t.message}</p>
                    </div>

                    <div class="space-y-4">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest">Admin Official Reply</label>
                        <textarea id="adminReplyText" class="w-full bg-white/5 border border-white/10 p-6 rounded-[2rem] outline-none text-sm h-40 focus:border-orange-500 transition" placeholder="Draft your professional response here...">${t.adminReply || ''}</textarea>
                        <div class="flex space-x-4">
                            <button onclick="updateTicket('${t._id}', 'Resolved')" class="flex-1 py-4 bg-emerald-600 text-white rounded-2xl text-[10px] font-black uppercase hover:scale-105 transition shadow-lg shadow-emerald-600/20">Resolve & Notify</button>
                            <button onclick="updateTicket('${t._id}', 'In Review')" class="flex-1 py-4 glass text-white rounded-2xl text-[10px] font-black uppercase hover:bg-white/5 transition">Save Draft</button>
                        </div>
                    </div>

                    <div class="space-y-6">
                        <h4 class="text-xs font-black text-white uppercase border-b border-white/5 pb-2">Internal Moderation Notes</h4>
                        <div id="internalNotes" class="space-y-4 max-h-40 overflow-y-auto pr-2">
                            ${t.internalNotes.map(n => `
                                <div class="glass p-4 rounded-2xl text-[11px]">
                                    <div class="flex justify-between mb-1">
                                        <span class="font-black text-orange-500 uppercase">${n.adminName || 'Admin'}</span>
                                        <span class="text-slate-500">${new Date(n.timestamp).toLocaleString()}</span>
                                    </div>
                                    <p class="text-slate-300">${n.note}</p>
                                </div>
                            `).join('')}
                        </div>
                        <div class="flex space-x-2">
                            <input type="text" id="newInternalNote" placeholder="Add private moderation note..." class="flex-1 bg-white/5 border border-white/10 px-4 py-3 rounded-xl outline-none text-xs focus:border-orange-500 transition">
                            <button onclick="addTicketNote('${t._id}')" class="px-6 glass text-white rounded-xl text-[10px] font-black uppercase hover:bg-white/10">Post</button>
                        </div>
                    </div>
                </div>

                <!-- Right: User Context & Tools -->
                <div class="space-y-8">
                    <div class="space-y-4">
                        <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest border-b border-white/5 pb-2">User Context</h4>
                        <div class="space-y-4">
                            <div class="flex justify-between items-center">
                                <span class="text-[10px] text-slate-400 font-bold uppercase">Name</span>
                                <span class="text-[10px] text-white font-black uppercase">${t.name}</span>
                            </div>
                            <div class="flex justify-between items-center">
                                <span class="text-[10px] text-slate-400 font-bold uppercase">Phone</span>
                                <span class="text-[10px] text-white font-black uppercase">${t.phone || 'N/A'}</span>
                            </div>
                            <div class="flex justify-between items-center">
                                <span class="text-[10px] text-slate-400 font-bold uppercase">Premium</span>
                                ${t.userContext?.premiumStatus ? UI.badge('Active', 'bg-orange-500 text-black') : UI.badge('Free', 'bg-slate-700 text-white')}
                            </div>
                             <div class="flex justify-between items-center">
                                <span class="text-[10px] text-slate-400 font-bold uppercase">Device</span>
                                <span class="text-[9px] text-slate-500 font-bold uppercase">${t.userContext?.deviceInfo || 'Unknown'}</span>
                            </div>
                        </div>
                    </div>

                    <div class="space-y-4">
                        <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest border-b border-white/5 pb-2">Ticket Management</h4>
                        <div class="space-y-3">
                             <label class="text-[9px] font-black text-slate-600 uppercase">Change Status</label>
                             <select id="ticketStatusSelect" class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-[10px] font-black uppercase text-white outline-none">
                                <option value="Pending" ${t.status === 'Pending' ? 'selected' : ''}>Pending</option>
                                <option value="In Review" ${t.status === 'In Review' ? 'selected' : ''}>In Review</option>
                                <option value="Escalated" ${t.status === 'Escalated' ? 'selected' : ''}>Escalated</option>
                                <option value="Waiting For User" ${t.status === 'Waiting For User' ? 'selected' : ''}>Waiting For User</option>
                                <option value="Resolved" ${t.status === 'Resolved' ? 'selected' : ''}>Resolved</option>
                                <option value="Closed" ${t.status === 'Closed' ? 'selected' : ''}>Closed</option>
                             </select>
                        </div>
                        <div class="space-y-3">
                             <label class="text-[9px] font-black text-slate-600 uppercase">Change Priority</label>
                             <select id="ticketPrioritySelect" class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-[10px] font-black uppercase text-white outline-none">
                                <option value="Low" ${t.priority === 'Low' ? 'selected' : ''}>Low</option>
                                <option value="Medium" ${t.priority === 'Medium' ? 'selected' : ''}>Medium</option>
                                <option value="High" ${t.priority === 'High' ? 'selected' : ''}>High</option>
                                <option value="Critical" ${t.priority === 'Critical' ? 'selected' : ''}>Critical</option>
                             </select>
                        </div>
                        <div class="space-y-3">
                             <label class="text-[9px] font-black text-slate-600 uppercase">Assign Agent</label>
                             <select id="ticketAssignSelect" class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-[10px] font-black uppercase text-white outline-none">
                                <option value="">Unassigned</option>
                                ${cachedAdmins.map(a => `<option value="${a._id}" ${t.assignedTo === a._id ? 'selected' : ''}>${a.username} (${a.role})</option>`).join('')}
                             </select>
                        </div>
                        <button onclick="saveTicketSettings('${t._id}')" class="w-full py-4 glass text-[10px] font-black uppercase hover:bg-orange-500 hover:text-black transition">Update Configuration</button>
                    </div>

                    <div class="p-6 rounded-[2rem] bg-red-500/5 border border-red-500/10 space-y-4">
                        <p class="text-[9px] font-black text-red-500 uppercase text-center">Moderation Overrides</p>
                        <button class="w-full py-3 bg-red-500/10 text-red-500 rounded-xl text-[9px] font-black uppercase hover:bg-red-500 hover:text-white transition">Ban Reported User</button>
                        <button class="w-full py-3 glass text-red-300 rounded-xl text-[9px] font-black uppercase hover:bg-red-500/20 transition">Flag as Fraud</button>
                    </div>
                </div>
            </div>
        `;
        UI.modal.show('Ticket Interaction Center', content);
    } catch (e) {
        UI.modal.show('Error', '<p class="p-10 text-center text-red-500 uppercase font-black">Failed to load ticket details</p>');
    }
}

async function updateTicket(id, status) {
    const adminReply = document.getElementById('adminReplyText').value;
    try {
        await API.updateTicket(id, { adminReply, status });
        UI.modal.hide();
        renderSupportList();
    } catch (e) { alert("Failed to update ticket"); }
}

async function saveTicketSettings(id) {
    const status = document.getElementById('ticketStatusSelect').value;
    const priority = document.getElementById('ticketPrioritySelect').value;
    const assignedTo = document.getElementById('ticketAssignSelect').value;
    const adminName = document.getElementById('ticketAssignSelect').options[document.getElementById('ticketAssignSelect').selectedIndex].text.split(' (')[0];

    try {
        await API.updateTicket(id, { status, priority, assignedTo, assignedToName: assignedTo ? adminName : null });
        UI.modal.hide();
        renderSupportList();
    } catch (e) { alert("Failed to save settings"); }
}

async function addTicketNote(id) {
    const note = document.getElementById('newInternalNote').value;
    if (!note) return;
    try {
        await API.addTicketNote(id, { note, adminName: 'Himanshu', adminId: null });
        document.getElementById('newInternalNote').value = '';
        viewSupportMessage(id); // Refresh view
    } catch (e) { alert("Failed to add note"); }
}
