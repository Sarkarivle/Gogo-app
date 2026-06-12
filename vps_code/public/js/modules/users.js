let currentUserFilters = {
    search: '',
    status: 'all',
    accountStatus: 'All',
    dateRange: 'all',
    trustLevel: 'all',
    userType: 'registered',
    sortBy: 'createdAt',
    sortOrder: 'desc',
    page: 1,
    limit: 50
};

let selectedUsers = new Set();

async function loadUsers(filters = {}) {
    // Merge provided filters with current state
    currentUserFilters = { ...currentUserFilters, ...filters };

    // Clear selection if we are changing page or filters (optional, but safer)
    if (filters.page || filters.search || filters.userType) {
        // selectedUsers.clear(); // Uncomment if you want to clear selection on navigation
    }

    const { search, status, accountStatus, dateRange, trustLevel, userType, sortBy, sortOrder, page, limit } = currentUserFilters;

    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "User Management";

    mainContent.innerHTML = `
        <div class="space-y-6">
            <!-- Analytics Overview -->
            <div id="userStatsContainer" class="grid grid-cols-1 md:grid-cols-5 gap-4">
                <div class="glass p-4 rounded-[1.5rem] animate-pulse"><div class="skeleton h-3 w-20 mb-2"></div><div class="skeleton h-8 w-32"></div></div>
                <div class="glass p-4 rounded-[1.5rem] animate-pulse"><div class="skeleton h-3 w-20 mb-2"></div><div class="skeleton h-8 w-32"></div></div>
                <div class="glass p-4 rounded-[1.5rem] animate-pulse"><div class="skeleton h-3 w-20 mb-2"></div><div class="skeleton h-8 w-32"></div></div>
                <div class="glass p-4 rounded-[1.5rem] animate-pulse"><div class="skeleton h-3 w-20 mb-2"></div><div class="skeleton h-8 w-32"></div></div>
                <div class="glass p-4 rounded-[1.5rem] animate-pulse"><div class="skeleton h-3 w-20 mb-2"></div><div class="skeleton h-8 w-32"></div></div>
            </div>

            <div class="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
                <div class="relative w-full md:w-80">
                    <i class="fas fa-search absolute left-5 top-1/2 -translate-y-1/2 text-slate-500"></i>
                    <input type="text" id="userSearch" value="${search}" onkeypress="if(event.key === 'Enter') applyUserFilters()" placeholder="Search Identity (Name or Phone)..." class="w-full bg-white/5 border border-white/5 p-4 pl-14 rounded-2xl outline-none text-sm focus:border-orange-500/50 transition">
                </div>

                <div class="flex flex-wrap items-center gap-3 w-full md:w-auto">
                    <select id="userTypeFilter" onchange="applyUserFilters()" class="glass bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs font-bold text-slate-300 focus:border-orange-500/50 transition">
                        <option value="registered" ${userType === 'registered' ? 'selected' : ''}>Premium & Free</option>
                        <option value="premium" ${userType === 'premium' ? 'selected' : ''}>Premium Only</option>
                        <option value="free" ${userType === 'free' ? 'selected' : ''}>Free Users Only</option>
                        <option value="unregistered" ${userType === 'unregistered' ? 'selected' : ''}>Unregistered</option>
                    </select>

                    <select id="dateRangeFilter" onchange="applyUserFilters()" class="glass bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs font-bold text-slate-300 focus:border-orange-500/50 transition">
                        <option value="all" ${dateRange === 'all' ? 'selected' : ''}>All Time</option>
                        <option value="today" ${dateRange === 'today' ? 'selected' : ''}>Today</option>
                        <option value="yesterday" ${dateRange === 'yesterday' ? 'selected' : ''}>Yesterday</option>
                        <option value="last7days" ${dateRange === 'last7days' ? 'selected' : ''}>Last 7 Days</option>
                    </select>

                    <select id="statusFilter" onchange="applyUserFilters()" class="glass bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs font-bold text-slate-300 focus:border-orange-500/50 transition">
                        <option value="all" ${status === 'all' ? 'selected' : ''}>Connection: All</option>
                        <option value="online" ${status === 'online' ? 'selected' : ''}>Online Only</option>
                        <option value="offline" ${status === 'offline' ? 'selected' : ''}>Offline Only</option>
                    </select>

                    <select id="accountStatusFilter" onchange="applyUserFilters()" class="glass bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs font-bold text-slate-300 focus:border-orange-500/50 transition">
                        <option value="All" ${accountStatus === 'All' ? 'selected' : ''}>Status: All</option>
                        <option value="Active" ${accountStatus === 'Active' ? 'selected' : ''}>Active</option>
                        <option value="Deactivated" ${accountStatus === 'Deactivated' ? 'selected' : ''}>Deactivated</option>
                        <option value="Suspended" ${accountStatus === 'Suspended' ? 'selected' : ''}>Suspended</option>
                    </select>

                    <div class="flex space-x-2">
                        <button id="bulkDeleteBtn" onclick="bulkDeleteSelected()" class="hidden glass p-4 rounded-2xl bg-red-500/10 text-red-500 border border-red-500/20 hover:bg-red-500 hover:text-white transition" title="Delete Selected"><i class="fas fa-trash-alt"></i></button>
                        <button onclick="loadUsers({search: '', status: 'all', accountStatus: 'All', dateRange: 'all', trustLevel: 'all', userType: 'registered', sortBy: 'createdAt', sortOrder: 'desc', page: 1})" class="glass p-4 rounded-2xl hover:bg-white/5 transition" title="Reset Filters"><i class="fas fa-sync-alt"></i></button>
                    </div>
                </div>
            </div>
            <div id="userTableContainer">${UI.skeletonTable(10)}</div>
            <div id="paginationContainer" class="flex justify-center items-center space-x-4 py-6"></div>
        </div>
    `;

    try {
        const response = await API.getUsers(currentUserFilters);
        const users = response.users || [];
        const stats = response.stats || { totalUsers: 0, onlineUsers: 0, todayJoined: 0, totalPremium: 0, todayPremium: 0 };
        const pagination = response.pagination || { page: 1, pages: 1, total: 0 };

        // Update Stats UI
        document.getElementById('userStatsContainer').innerHTML = `
            <div class="glass p-5 rounded-[1.5rem] border-b-2 border-orange-500/20">
                <p class="text-[9px] font-black text-slate-500 uppercase mb-1 tracking-widest">Total Registry</p>
                <h3 class="text-2xl font-black text-white">${stats.totalUsers.toLocaleString()} <span class="text-[9px] text-slate-500 ml-1 font-bold">USERS</span></h3>
            </div>
            <div class="glass p-5 rounded-[1.5rem] border-b-2 border-orange-400/40">
                <p class="text-[9px] font-black text-orange-400 uppercase mb-1 tracking-widest">Total Premium</p>
                <h3 class="text-2xl font-black text-white">${(stats.totalPremium || 0).toLocaleString()} <span class="text-[9px] text-orange-400 ml-1 font-bold">PRO</span></h3>
            </div>
            <div class="glass p-5 rounded-[1.5rem] border-b-2 border-emerald-500/20">
                <p class="text-[9px] font-black text-slate-500 uppercase mb-1 tracking-widest">Currently Online</p>
                <h3 class="text-2xl font-black text-emerald-500">${stats.onlineUsers.toLocaleString()} <span class="text-[9px] text-slate-500 ml-1 font-bold">ACTIVE</span></h3>
            </div>
            <div class="glass p-5 rounded-[1.5rem] border-b-2 border-blue-500/20">
                <p class="text-[9px] font-black text-slate-500 uppercase mb-1 tracking-widest">New Today</p>
                <h3 class="text-2xl font-black text-blue-400">+${stats.todayJoined.toLocaleString()} <span class="text-[9px] text-slate-500 ml-1 font-bold">JOINED</span></h3>
            </div>
            <div class="glass p-5 rounded-[1.5rem] border-b-2 border-blue-400/40">
                <p class="text-[9px] font-black text-blue-400 uppercase mb-1 tracking-widest">Today Premium</p>
                <h3 class="text-2xl font-black text-white">+${(stats.todayPremium || 0).toLocaleString()} <span class="text-[9px] text-blue-400 ml-1 font-bold">PRO</span></h3>
            </div>
        `;

        const rows = users.map(u => {
            const genderColor = u.gender === 'Male' ? 'text-blue-400' : (u.gender === 'Female' ? 'text-pink-400' : 'text-slate-400');
            const genderIcon = u.gender === 'Male' ? 'fa-mars' : (u.gender === 'Female' ? 'fa-venus' : 'fa-genderless');
            const isSelected = selectedUsers.has(u.phone);

            return `
                <tr class="hover:bg-white/[0.01] transition-colors">
                    <td class="p-6">
                        <input type="checkbox" onchange="toggleUserSelection('${u.phone}')" ${isSelected ? 'checked' : ''} class="user-checkbox w-4 h-4 rounded border-white/10 bg-white/5 checked:bg-orange-500 transition cursor-pointer">
                    </td>
                    <td class="p-6">
                        <div class="flex items-center space-x-3">
                            <div class="relative">
                                <div class="w-12 h-12 rounded-2xl bg-white/5 flex items-center justify-center text-slate-500 font-black border-2 ${u.isPremium ? 'border-orange-500' : 'border-white/10'}">
                                    ${u.name ? u.name[0] : '?'}
                                </div>
                                ${u.isVerified ? `
                                    <div class="absolute -top-1 -right-1 bg-blue-500 text-white w-4 h-4 rounded-full flex items-center justify-center border-2 border-[#0b0d13]">
                                        <i class="fas fa-check text-[7px]"></i>
                                    </div>
                                ` : ''}
                            </div>
                            <div>
                                <div class="flex items-center space-x-1">
                                    <p class="text-sm font-bold text-white">${u.name || 'Incognito'}</p>
                                    <i class="fas ${genderIcon} ${genderColor} text-[10px]"></i>
                                    ${u.isPremium ? '<i class="fas fa-crown text-orange-500 text-[10px] ml-1"></i>' : ''}
                                </div>
                                <div class="flex items-center space-x-2">
                                    <p class="text-[10px] text-slate-500">${u.phone}</p>
                                    ${u.multiAccountCount > 1 ? `<span class="px-1.5 py-0.5 bg-red-500/10 text-red-500 text-[8px] font-black rounded uppercase">Multi-UID: ${u.multiAccountCount}</span>` : ''}
                                </div>
                            </div>
                        </div>
                    </td>
                    <td class="p-6">
                        <p class="text-xs font-bold text-white">${u.city || 'Global'}</p>
                        <p class="text-[9px] text-slate-500 font-bold uppercase">Joined ${timeAgo(u.createdAt)}</p>
                    </td>
                    <td class="p-6">
                        <div class="flex items-center space-x-2">
                            <div class="w-1.5 h-1.5 rounded-full ${u.trustScore >= 80 ? 'bg-emerald-500' : (u.trustScore >= 40 ? 'bg-yellow-500' : 'bg-red-500')}"></div>
                            <span class="text-[10px] font-black uppercase ${u.trustScore >= 80 ? 'text-emerald-500' : (u.trustScore >= 40 ? 'text-yellow-500' : 'text-red-500')}">${u.trustScore}%</span>
                        </div>
                    </td>
                    <td class="p-6">
                        <div class="flex items-center space-x-2">
                            <div class="w-2 h-2 rounded-full ${u.isOnline ? 'bg-emerald-500 animate-pulse' : 'bg-slate-700'}"></div>
                            <div>
                                <p class="text-[10px] font-black uppercase ${u.isOnline ? 'text-emerald-500' : 'text-slate-500'}">${u.isOnline ? 'Online' : 'Offline'}</p>
                                ${!u.isOnline && u.lastSeen ? `<p class="text-[8px] text-slate-600 font-bold uppercase">${timeAgo(u.lastSeen)}</p>` : ''}
                            </div>
                        </div>
                    </td>
                    <td class="p-6">
                        <div class="flex flex-col space-y-1">
                            ${(() => {
                                const status = u.accountStatus || 'Active';
                                let colors = 'bg-emerald-500/10 text-emerald-500';
                                if (status === 'Deactivated') colors = 'bg-orange-500/10 text-orange-500';
                                else if (status !== 'Active') colors = 'bg-red-500/10 text-red-500';
                                return UI.badge(status, colors);
                            })()}
                            ${u.isShadowBanned ? UI.badge('Shadow', 'bg-purple-500/10 text-purple-500') : ''}
                        </div>
                    </td>
                    <td class="p-6">
                        <div class="flex items-center space-x-2">
                            <button onclick="quickToggleVerify('${u.phone}', ${u.isVerified})" class="w-8 h-8 rounded-lg flex items-center justify-center transition ${u.isVerified ? 'bg-blue-500/20 text-blue-500' : 'bg-white/5 text-slate-500 hover:bg-white/10'}" title="Quick Verify">
                                <i class="fas fa-check-circle text-[10px]"></i>
                            </button>
                            <button onclick="quickToggleShadow('${u.phone}', ${u.isShadowBanned})" class="w-8 h-8 rounded-lg flex items-center justify-center transition ${u.isShadowBanned ? 'bg-purple-500/20 text-purple-500' : 'bg-white/5 text-slate-500 hover:bg-white/10'}" title="Quick Shadow Ban">
                                <i class="fas fa-user-secret text-[10px]"></i>
                            </button>
                            <button onclick="openUserControl('${u.phone}', 'inbox')" class="w-8 h-8 rounded-lg flex items-center justify-center transition bg-white/5 text-slate-500 hover:bg-blue-500/10 hover:text-blue-500" title="View Chats">
                                <i class="fas fa-comments text-[10px]"></i>
                            </button>
                        </div>
                    </td>
                    <td class="p-6 text-right">
                        <button onclick="openUserControl('${u.phone}')" class="px-6 py-2 bg-orange-500 text-black rounded-xl text-[10px] font-black uppercase transition hover:scale-105">Manage</button>
                    </td>
                </tr>
            `;
        });

        const getSortIcon = (field) => {
            if (sortBy !== field) return '<i class="fas fa-sort ml-2 opacity-20"></i>';
            return sortOrder === 'asc' ? '<i class="fas fa-sort-up ml-2 text-orange-500"></i>' : '<i class="fas fa-sort-down ml-2 text-orange-500"></i>';
        };

        const headers = [
            `<input type="checkbox" id="selectAllUsers" onchange="toggleSelectAll(this)" class="w-4 h-4 rounded border-white/10 bg-white/5 checked:bg-orange-500 transition cursor-pointer">`,
            `<div class="flex items-center cursor-pointer select-none" onclick="toggleSort('name')">User Identity ${getSortIcon('name')}</div>`,
            `<div class="flex items-center cursor-pointer select-none" onclick="toggleSort('createdAt')">Joined ${getSortIcon('createdAt')}</div>`,
            `<div class="flex items-center cursor-pointer select-none" onclick="toggleSort('trustScore')">Integrity ${getSortIcon('trustScore')}</div>`,
            `<div class="flex items-center cursor-pointer select-none" onclick="toggleSort('lastSeen')">Status ${getSortIcon('lastSeen')}</div>`,
            `<div class="flex items-center cursor-pointer select-none" onclick="toggleSort('accountStatus')">Account Status ${getSortIcon('accountStatus')}</div>`,
            'Quick Actions',
            'Action'
        ];

        document.getElementById('userTableContainer').innerHTML = UI.table(
            headers,
            rows
        );

        // Update Bulk Button visibility
        updateBulkButton();

        // Update Pagination
        const pagContainer = document.getElementById('paginationContainer');
        if (pagination.pages > 1) {
            pagContainer.innerHTML = `
                <button onclick="loadUsers({page: ${pagination.page - 1}})" ${pagination.page === 1 ? 'disabled' : ''} class="px-6 py-3 glass rounded-xl text-[10px] font-black uppercase disabled:opacity-20 transition hover:bg-white/5">
                    <i class="fas fa-chevron-left mr-2"></i> Previous
                </button>
                <span class="text-[10px] font-black text-slate-500 uppercase">Page ${pagination.page} of ${pagination.pages}</span>
                <button onclick="loadUsers({page: ${pagination.page + 1}})" ${pagination.page === pagination.pages ? 'disabled' : ''} class="px-6 py-3 glass rounded-xl text-[10px] font-black uppercase disabled:opacity-20 transition hover:bg-white/5">
                    Next <i class="fas fa-chevron-right ml-2"></i>
                </button>
            `;
        } else {
            pagContainer.innerHTML = '';
        }

    } catch (err) {
        console.error("loadUsers Error:", err);
        document.getElementById('userTableContainer').innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error syncing user registry</p>`;
    }
}

function timeAgo(date) {
    if (!date) return 'Never';
    const seconds = Math.floor((new Date() - new Date(date)) / 1000);
    let interval = seconds / 31536000;
    if (interval > 1) return Math.floor(interval) + "y ago";
    interval = seconds / 2592000;
    if (interval > 1) return Math.floor(interval) + "mo ago";
    interval = seconds / 86400;
    if (interval > 1) return Math.floor(interval) + "d ago";
    interval = seconds / 3600;
    if (interval > 1) return Math.floor(interval) + "h ago";
    interval = seconds / 60;
    if (interval > 1) return Math.floor(interval) + "m ago";
    return "Just now";
}

async function openUserControl(phone, initialTab = 'timeline') {
    UI.modal.show(
        `<div class="flex items-center space-x-4"><div class="custom-loader w-8 h-8"></div><p class="text-xs uppercase font-black">Fetching full user profile...</p></div>`,
        UI.loader()
    );

    try {
        const data = await API.getUserFull(phone);
        const u = data.user;
        const reports = data.reportsAgainst || [];

        // Calculate Trust Score
        let score = 70;
        if (u.isVerified) score += 15;
        if (u.isPremium) score += 10;
        if (u.isShadowBanned) score -= 30;
        if (u.accountStatus === 'Suspended' || u.accountStatus === 'Banned') score = 0;
        if (reports.length > 0) score -= (reports.length * 5);
        if (u.deviceHistory && u.deviceHistory.length > 2) score -= (u.deviceHistory.length * 3);
        const trustScore = Math.max(0, Math.min(100, score));

        UI.modal.show(
            `
            <div class="flex items-center justify-between w-full">
                <div class="flex items-center space-x-4">
                    <div class="relative">
                        <div class="w-14 h-14 rounded-2xl bg-orange-500 flex items-center justify-center text-black font-black text-2xl">
                            ${u.name ? u.name[0] : '?'}
                        </div>
                        ${u.isPremium ? `
                            <div class="absolute -top-1 -right-1 bg-orange-500 text-black w-5 h-5 rounded-lg flex items-center justify-center border-2 border-[#0b0d13]">
                                <i class="fas fa-crown text-[10px]"></i>
                            </div>
                        ` : ''}
                    </div>
                    <div>
                        <div class="flex items-center space-x-2">
                            <h2 class="text-xl font-black text-white uppercase">${u.name || 'Anonymous'}</h2>
                            ${u.isVerified ? '<i class="fas fa-check-circle text-blue-500 text-sm"></i>' : ''}
                        </div>
                        <p class="text-xs text-orange-500 font-bold">${u.phone}</p>
                    </div>
                </div>
                <div class="flex flex-col items-end">
                    <p class="text-[9px] font-black text-slate-500 uppercase mb-1 tracking-widest">Integrity Score</p>
                    <div class="flex items-center space-x-2 bg-white/5 px-4 py-2 rounded-xl border border-white/5">
                        <div class="w-2 h-2 rounded-full ${trustScore >= 80 ? 'bg-emerald-500 animate-pulse' : (trustScore >= 40 ? 'bg-yellow-500' : 'bg-red-500 animate-bounce')}"></div>
                        <span class="text-sm font-black ${trustScore >= 80 ? 'text-emerald-500' : (trustScore >= 40 ? 'text-yellow-500' : 'text-red-500')}">${trustScore}%</span>
                    </div>
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
                    <div class="flex space-x-3 shrink-0 overflow-x-auto pb-2 scrollbar-hide">
                        <button onclick="loadUserTimeline('${u.phone}')" id="tab-timeline" class="flex-1 min-w-[100px] glass p-4 rounded-2xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-stream mr-2 text-orange-500"></i> Timeline</button>
                        <button onclick="loadUserInbox('${u.phone}')" id="tab-inbox" class="flex-1 min-w-[100px] glass p-4 rounded-2xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-inbox mr-2 text-blue-500"></i> Inbox</button>
                        <button onclick="loadUserFinance('${u.phone}')" id="tab-finance" class="flex-1 min-w-[100px] glass p-4 rounded-2xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-credit-card mr-2 text-emerald-500"></i> Finance</button>
                        <button onclick="loadUserMedia('${u.phone}')" id="tab-media" class="flex-1 min-w-[100px] glass p-4 rounded-2xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-images mr-2 text-purple-500"></i> Media</button>
                        <button onclick="loadUserSecurity('${u.phone}')" id="tab-security" class="flex-1 min-w-[100px] glass p-4 rounded-2xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-shield-alt mr-2 text-red-500"></i> Security</button>
                        <button onclick="openNotificationModal('${u.phone}')" id="tab-notify" class="flex-1 min-w-[100px] glass p-4 rounded-2xl text-[9px] font-black uppercase hover:bg-white/5"><i class="fas fa-bell mr-2 text-yellow-500"></i> Notify</button>
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

        // Load initial tab
        if (initialTab === 'inbox') loadUserInbox(phone);
        else loadUserTimeline(phone);

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
        const reports = data.reportsAgainst || [];
        const blocks = data.blockedBy || [];

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
                    <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-4 border-b border-white/5 pb-2">Block Registry (Blocked By ${blocks.length} Users)</h4>
                    <div class="space-y-2">
                        ${blocks.map(b => `
                            <div class="p-4 bg-orange-500/5 border border-orange-500/10 rounded-2xl">
                                <div class="flex justify-between items-start mb-2">
                                    <p class="text-[10px] font-black text-white uppercase">BY: ${b.blockerName || 'Anonymous'}</p>
                                    <span class="text-[7px] text-slate-500 font-black uppercase">${new Date(b.timestamp).toLocaleString()}</span>
                                </div>
                                <p class="text-[10px] text-slate-400 italic">Reason: "${b.reason || 'Manual Block'}"</p>
                            </div>
                        `).join('') || '<p class="text-center py-10 opacity-20 uppercase font-black text-[10px]">Not blocked by anyone</p>'}
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

async function loadUserFinance(phone, filter = 'all') {
    UI.modal.setDynamicContent(UI.skeletonModal());
    try {
        const data = await API.getUserFull(phone);
        const user = data.user || {};
        const sub = user.subscription || {};
        let payments = data.paymentHistory || [];

        // Calculate Total Spent (only successful transactions)
        const totalSpent = payments
            .filter(p => ['captured', 'success', 'active', 'SUCCESS'].includes(p.status?.toLowerCase() || p.status))
            .reduce((acc, p) => acc + (p.amount || 0), 0);

        // Filter payments for display
        if (filter !== 'all') {
            payments = payments.filter(p => {
                const s = p.status?.toLowerCase() || p.status;
                if (filter === 'success') return ['captured', 'success', 'active', 'SUCCESS'].includes(s);
                if (filter === 'pending') return ['created', 'pending', 'PENDING'].includes(s);
                if (filter === 'failed') return ['failed', 'refunded', 'FAILED', 'CANCELLED'].includes(s);
                return true;
            });
        }

        const content = `
            <div class="space-y-8 animate-fade">
                <!-- Subscription Card -->
                <div class="glass p-8 rounded-3xl bg-emerald-500/5 border border-emerald-500/10">
                    <div class="flex justify-between items-start mb-6">
                        <div>
                            <p class="text-[10px] font-black text-slate-500 uppercase tracking-widest mb-1">Active Subscription</p>
                            <h3 class="text-xl font-black text-white uppercase">${user.premiumPlan || 'Free Tier'}</h3>
                            <div class="flex items-center space-x-2 mt-2">
                                <div class="w-2 h-2 rounded-full ${user.isPremium ? 'bg-orange-500 animate-pulse' : 'bg-slate-600'}"></div>
                                <p class="text-[9px] font-black uppercase ${user.isPremium ? 'text-orange-500' : 'text-slate-500'}">
                                    ${user.isPremium ? 'PREMIUM USER' : 'FREE USER'}
                                </p>
                            </div>
                        </div>
                        <div class="flex flex-col items-end">
                             <div class="flex space-x-2">
                                <button onclick="syncUserFinance('${phone}')" class="p-2 glass rounded-lg text-white hover:bg-white/10 transition" title="Sync with Provider">
                                    <i class="fas fa-sync-alt text-[10px]"></i>
                                </button>
                                ${UI.badge(sub.status || (user.isPremium ? 'Active' : 'None'), (sub.status === 'active' || user.isPremium) ? 'bg-emerald-500 text-black' : 'bg-slate-700 text-white')}
                             </div>
                             <p class="text-[8px] font-black text-slate-500 uppercase mt-2">Source: ${sub.paymentMethod || 'Manual'}</p>
                        </div>
                    </div>

                    <div class="grid grid-cols-2 md:grid-cols-4 gap-6">
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase">Valid Until</p>
                            <p class="text-xs font-bold text-white">${user.premiumExpiry ? new Date(user.premiumExpiry).toLocaleDateString() : 'N/A'}</p>
                        </div>
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase">Next Billing</p>
                            <p class="text-xs font-bold text-blue-400">${sub.nextBillingDate ? new Date(sub.nextBillingDate).toLocaleDateString() : 'N/A'}</p>
                        </div>
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase">Auto Renew</p>
                            <p class="text-xs font-bold ${sub.autoRenew ? 'text-emerald-500' : 'text-red-500'}">${sub.autoRenew ? 'ENABLED' : 'DISABLED'}</p>
                        </div>
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase">Last Paid</p>
                            <p class="text-xs font-bold text-orange-500">₹${sub.lastAmountPaid || 0}</p>
                        </div>
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase">Total Spent</p>
                            <p class="text-xs font-bold text-emerald-500">₹${totalSpent}</p>
                        </div>
                    </div>

                    ${sub.id ? `
                        <div class="mt-6 pt-4 border-t border-white/5">
                            <p class="text-[7px] font-black text-slate-600 uppercase">Provider ID</p>
                            <p class="text-[9px] font-mono text-slate-400">${sub.id}</p>
                        </div>
                    ` : ''}
                </div>

                <!-- Payment Logs Header & Filters -->
                <div>
                    <div class="flex justify-between items-center mb-4 border-b border-white/5 pb-2">
                        <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest">Transaction History</h4>
                        <div class="flex space-x-2">
                            <button onclick="loadUserFinance('${phone}', 'all')" class="px-3 py-1 rounded-lg text-[8px] font-black uppercase ${filter === 'all' ? 'bg-white/10 text-white' : 'text-slate-500 hover:text-white'}">All</button>
                            <button onclick="loadUserFinance('${phone}', 'success')" class="px-3 py-1 rounded-lg text-[8px] font-black uppercase ${filter === 'success' ? 'bg-emerald-500 text-black shadow-lg shadow-emerald-500/20' : 'text-slate-500 hover:text-emerald-500'}">Success</button>
                            <button onclick="loadUserFinance('${phone}', 'pending')" class="px-3 py-1 rounded-lg text-[8px] font-black uppercase ${filter === 'pending' ? 'bg-yellow-500 text-black shadow-lg shadow-yellow-500/20' : 'text-slate-500 hover:text-yellow-500'}">Pending</button>
                            <button onclick="loadUserFinance('${phone}', 'failed')" class="px-3 py-1 rounded-lg text-[8px] font-black uppercase ${filter === 'failed' ? 'bg-red-500 text-white shadow-lg shadow-red-500/20' : 'text-slate-500 hover:text-red-500'}">Failed</button>
                        </div>
                    </div>
                    <div class="space-y-2">
                        ${payments.map(p => {
                            const s = p.status?.toLowerCase() || p.status;
                            const isSuccess = ['captured', 'success', 'active', 'SUCCESS'].includes(s);
                            const isFailed = ['failed', 'refunded', 'FAILED', 'CANCELLED'].includes(s);
                            const color = isSuccess ? 'text-emerald-500' : (isFailed ? 'text-red-500' : 'text-yellow-500');

                            return `
                                <div class="flex items-center justify-between p-4 bg-white/5 rounded-2xl border border-white/5">
                                    <div class="flex-1">
                                        <p class="text-[10px] font-black text-white uppercase">${p.orderId || 'Direct Payment'}</p>
                                        <div class="flex items-center space-x-2 mt-1">
                                            <p class="text-[8px] text-slate-500 font-bold uppercase">${new Date(p.createdAt || p.timestamp).toLocaleString()}</p>
                                            ${p.method ? `<span class="text-[7px] bg-white/5 px-2 py-0.5 rounded text-slate-400 uppercase font-bold">${p.method}</span>` : ''}
                                        </div>
                                    </div>
                                    <div class="text-right">
                                        <p class="text-[10px] font-black ${color} uppercase">₹${p.amount}</p>
                                        <p class="text-[8px] text-slate-500 font-bold uppercase">${p.status}</p>
                                    </div>
                                </div>
                            `;
                        }).join('') || '<p class="text-center py-10 opacity-20 uppercase font-black text-[10px]">No payments found matching filter</p>'}
                    </div>
                </div>
            </div>
        `;
        UI.modal.setDynamicContent(content);
    } catch (e) {
        console.error("loadUserFinance Error:", e);
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load finance data</p>');
    }
}

async function syncUserFinance(phone) {
    const btn = event.currentTarget;
    const icon = btn.querySelector('i');
    icon.classList.add('animate-spin');
    btn.disabled = true;

    try {
        const res = await API.syncProvider(phone);
        if (res.success) {
            UI.showToast("Sync Complete", "User status updated from provider", "bg-emerald-500");
            loadUserFinance(phone);
        } else {
            UI.showToast("Sync Failed", res.message || "Could not sync status", "bg-red-500");
        }
    } catch (e) {
        UI.showToast("Error", e.message, "bg-red-500");
    } finally {
        icon.classList.remove('animate-spin');
        btn.disabled = false;
    }
}

async function loadUserMedia(phone) {
    UI.modal.setDynamicContent(UI.skeletonModal());
    try {
        // Fetch both user profile and all media filtered by this user
        const [profileData, mediaData] = await Promise.all([
            API.getUserFull(phone),
            API.getAllMedia(phone)
        ]);

        const media = mediaData.media || [];

        const content = `
            <div class="space-y-6 animate-fade">
                <div class="flex justify-between items-center border-b border-white/5 pb-2">
                    <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest">Media Assets (${media.length})</h4>
                    <div class="flex space-x-2">
                        <span class="flex items-center text-[8px] font-bold text-slate-500 uppercase"><div class="w-1.5 h-1.5 rounded-full bg-blue-500 mr-1.5"></div> Profile</span>
                        <span class="flex items-center text-[8px] font-bold text-slate-500 uppercase ml-3"><div class="w-1.5 h-1.5 rounded-full bg-emerald-500 mr-1.5"></div> Recent</span>
                        <span class="flex items-center text-[8px] font-bold text-slate-500 uppercase ml-3"><div class="w-1.5 h-1.5 rounded-full bg-orange-500 mr-1.5"></div> Chat</span>
                    </div>
                </div>

                <div class="grid grid-cols-3 gap-4">
                    ${media.map(m => {
                        let borderColor = 'border-orange-500/20';
                        let badgeColor = 'bg-orange-500 text-black';
                        if (m.type === 'Profile') { borderColor = 'border-blue-500/20'; badgeColor = 'bg-blue-500 text-white'; }
                        else if (m.type === 'Recent') { borderColor = 'border-emerald-500/20'; badgeColor = 'bg-emerald-500 text-black'; }
                        else if (m.type === 'Video') { badgeColor = 'bg-purple-500 text-white'; }

                        const isAudio = m.type === 'Audio';
                        const authenticatedUrl = API.getAuthUrl(m.url);

                        return `
                            <div class="relative aspect-square rounded-2xl overflow-hidden group border-2 ${borderColor}">
                                ${isAudio ? `
                                    <div class="w-full h-full bg-white/5 flex flex-col items-center justify-center space-y-2">
                                        <i class="fas fa-microphone text-2xl text-slate-500"></i>
                                        <p class="text-[8px] font-bold uppercase text-slate-400">Audio Note</p>
                                    </div>
                                ` : `
                                    <img src="${authenticatedUrl}" class="w-full h-full object-cover" onerror="this.src='https://placehold.co/400x400?text=Image+Not+Found'">
                                `}

                                <!-- Overlay Info -->
                                <div class="absolute top-2 left-2">
                                    <span class="px-2 py-0.5 rounded text-[7px] font-black uppercase ${badgeColor}">
                                        ${m.type}
                                    </span>
                                </div>

                                <!-- Hover Actions -->
                                <div class="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 transition flex items-center justify-center space-x-3">
                                    <button onclick="window.open('${authenticatedUrl}')" class="w-10 h-10 glass rounded-full flex items-center justify-center text-xs hover:bg-white/10 transition">
                                        <i class="fas ${isAudio ? 'fa-play' : 'fa-expand'}"></i>
                                    </button>
                                    <button onclick="deleteUserSpecificMedia('${phone}', '${m.url}', '${m.type}')" class="w-10 h-10 bg-red-500 text-white rounded-full flex items-center justify-center text-xs hover:scale-110 transition">
                                        <i class="fas fa-trash"></i>
                                    </button>
                                </div>

                                <div class="absolute bottom-0 inset-x-0 p-2 bg-black/40 backdrop-blur-sm transform translate-y-full group-hover:translate-y-0 transition">
                                    <p class="text-[8px] text-white font-bold uppercase truncate">${new Date(m.timestamp).toLocaleDateString()} • ${new Date(m.timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}</p>
                                </div>
                            </div>
                        `;
                    }).join('') || `
                        <div class="col-span-3 py-20 flex flex-col items-center justify-center opacity-20">
                            <i class="fas fa-images text-5xl mb-4"></i>
                            <p class="uppercase font-black text-[10px] tracking-widest">No Media Uploaded Yet</p>
                        </div>
                    `}
                </div>
            </div>
        `;
        UI.modal.setDynamicContent(content);
    } catch (e) {
        console.error("loadUserMedia Error:", e);
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load media assets</p>');
    }
}

async function deleteUserSpecificMedia(phone, url, type) {
    if (!confirm(`Are you sure you want to delete this ${type} image permanently?`)) return;

    try {
        const res = await API.deleteMedia({ url, owner: phone, type });
        if (res.success) {
            UI.showToast("Success", "Media deleted successfully", "bg-emerald-500");
            loadUserMedia(phone); // Refresh the tab
        } else {
            UI.showToast("Error", res.message || "Failed to delete media", "bg-red-500");
        }
    } catch (e) {
        UI.showToast("Error", "System error while deleting", "bg-red-500");
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
    } catch (err) {
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load logs</p>');
    }
}

async function loadUserTimeline(phone) {
    UI.modal.setDynamicContent(UI.skeletonModal());
    try {
        const data = await API.getUserTimeline(phone);
        const timeline = data.timeline || [];

        const content = `
            <div class="space-y-6 animate-fade">
                <h4 class="text-[10px] font-black text-slate-500 uppercase tracking-widest border-b border-white/5 pb-4 mb-8">Activity Timeline (User Journey)</h4>

                <div class="relative ml-4 border-l-2 border-white/5 space-y-10 pb-10">
                    ${timeline.map(item => `
                        <div class="relative pl-10">
                            <!-- Dot -->
                            <div class="absolute -left-[9px] top-0 w-4 h-4 rounded-full bg-[#0b0d13] border-2 border-orange-500 flex items-center justify-center">
                                <div class="w-1 h-1 rounded-full bg-orange-500"></div>
                            </div>

                            <!-- Content -->
                            <div class="glass p-6 rounded-3xl border border-white/5 hover:border-white/10 transition group">
                                <div class="flex justify-between items-start mb-2">
                                    <div class="flex items-center space-x-3">
                                        <i class="fas ${item.icon} ${item.color} text-sm"></i>
                                        <h5 class="text-xs font-black text-white uppercase tracking-tight">${item.title}</h5>
                                    </div>
                                    <span class="text-[8px] font-bold text-slate-500 uppercase">${new Date(item.timestamp).toLocaleString()}</span>
                                </div>
                                <p class="text-[10px] text-slate-400 font-medium">${item.description}</p>
                            </div>
                        </div>
                    `).join('') || `
                        <div class="flex flex-col items-center justify-center py-20 opacity-20">
                            <i class="fas fa-history text-5xl mb-4"></i>
                            <p class="uppercase font-black text-[10px] tracking-widest">No activity logs found</p>
                        </div>
                    `}
                </div>
            </div>
        `;
        UI.modal.setDynamicContent(content);
    } catch (e) {
        UI.modal.setDynamicContent('<p class="text-red-500">Failed to load timeline</p>');
    }
}

function applyUserFilters() {
    const search = document.getElementById('userSearch')?.value || '';
    const status = document.getElementById('statusFilter')?.value || 'all';
    const accountStatus = document.getElementById('accountStatusFilter')?.value || 'All';
    const dateRange = document.getElementById('dateRangeFilter')?.value || 'all';
    const userType = document.getElementById('userTypeFilter')?.value || 'registered';

    loadUsers({ search, status, accountStatus, dateRange, userType, page: 1 });
}

function toggleSort(field) {
    const newOrder = (currentUserFilters.sortBy === field && currentUserFilters.sortOrder === 'asc') ? 'desc' : 'asc';
    loadUsers({ sortBy: field, sortOrder: newOrder });
}

async function quickToggleVerify(phone, current) {
    try {
        await API.updateUserStatus(phone, { isVerified: !current });
        UI.showToast("Success", `User ${!current ? 'Verified' : 'Unverified'}`, "bg-blue-500");
        loadUsers();
    } catch (e) { UI.showToast("Error", "Action failed", "bg-red-500"); }
}

async function quickToggleShadow(phone, current) {
    try {
        await API.updateUserStatus(phone, { isShadowBanned: !current });
        UI.showToast("Success", `Shadow Ban ${!current ? 'Enabled' : 'Disabled'}`, "bg-purple-500");
        loadUsers();
    } catch (e) { UI.showToast("Error", "Action failed", "bg-red-500"); }
}

async function quickBanUser(phone, currentStatus) {
    const newStatus = currentStatus === 'Suspended' ? 'Active' : 'Suspended';
    if (!confirm(`Are you sure you want to ${newStatus === 'Suspended' ? 'BAN' : 'RESTORE'} this user?`)) return;

    try {
        await API.updateUserStatus(phone, { accountStatus: newStatus });
        UI.showToast("Success", `User status changed to ${newStatus}`, newStatus === 'Suspended' ? "bg-red-500" : "bg-emerald-500");
        loadUsers();
    } catch (e) { UI.showToast("Error", "Action failed", "bg-red-500"); }
}

function toggleUserSelection(phone) {
    if (selectedUsers.has(phone)) {
        selectedUsers.delete(phone);
    } else {
        selectedUsers.add(phone);
    }
    updateBulkButton();
}

function toggleSelectAll(master) {
    const checkboxes = document.querySelectorAll('.user-checkbox');
    checkboxes.forEach(cb => {
        cb.checked = master.checked;
        const phone = cb.getAttribute('onchange').match(/'([^']+)'/)[1];
        if (master.checked) {
            selectedUsers.add(phone);
        } else {
            selectedUsers.delete(phone);
        }
    });
    updateBulkButton();
}

function updateBulkButton() {
    const btn = document.getElementById('bulkDeleteBtn');
    if (!btn) return;
    if (selectedUsers.size > 0) {
        btn.classList.remove('hidden');
    } else {
        btn.classList.add('hidden');
    }
}

async function bulkDeleteSelected() {
    const count = selectedUsers.size;
    if (count === 0) return;

    if (!confirm(`🧨 DANGER ZONE: Are you sure you want to PERMANENTLY DELETE ${count} selected users? This will wipe all their data including chats, media, and payments. This action cannot be undone.`)) {
        return;
    }

    UI.showToast("Wiping Data", `Executing bulk deletion for ${count} users...`, "bg-orange-500");

    try {
        const phones = Array.from(selectedUsers);
        const res = await API.bulkDeleteUsers(phones);

        if (res.success) {
            UI.showToast("Success", res.message, "bg-emerald-500");
            selectedUsers.clear();
            loadUsers();
        } else {
            UI.showToast("Error", res.message || "Bulk deletion failed", "bg-red-500");
        }
    } catch (e) {
        UI.showToast("Critical Error", e.message, "bg-red-500");
    }
}
