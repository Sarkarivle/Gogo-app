let allReports = [];

async function loadReports() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Security Incidents";

    // Show initial skeleton
    mainContent.innerHTML = `
        <div class="space-y-8 animate-fade">
            <div class="grid grid-cols-4 gap-6">
                ${UI.skeletonCard()}${UI.skeletonCard()}${UI.skeletonCard()}${UI.skeletonCard()}
            </div>
            ${UI.skeletonTable(10)}
        </div>
    `;

    try {
        const response = await API.getReports();
        allReports = Array.isArray(response) ? response : (response.reports || []);

        renderReportsUI();
    } catch (err) {
        console.error(err);
        mainContent.innerHTML = `<div class="p-20 text-center"><p class="text-red-500 uppercase font-black">Error synchronizing security feed</p><p class="text-xs text-slate-500 mt-2">${err.message}</p></div>`;
    }
}

function renderReportsUI(filteredReports = null) {
    const reports = filteredReports || allReports;
    const mainContent = document.getElementById('mainContent');

    const pendingCount = allReports.filter(r => r.status === 'Pending').length;
    const resolvedCount = allReports.filter(r => r.status === 'Resolved' || r.status === 'Dismissed').length;
    const highRiskCount = allReports.filter(r => r.category && (r.category.toLowerCase().includes('abusive') || r.category.toLowerCase().includes('harassment'))).length;

    const statsHtml = `
        <div class="grid grid-cols-4 gap-6 mb-10">
            ${UI.card('Total Incidents', allReports.length, 'Lifetime tracking', 'text-white')}
            ${UI.card('Pending Action', pendingCount, 'Needs immediate review', 'text-yellow-500')}
            ${UI.card('Resolved', resolvedCount, 'Moderated successfully', 'text-emerald-500')}
            ${UI.card('High Risk', highRiskCount, 'Severe violations', 'text-red-500')}
        </div>
    `;

    const filterHtml = `
        <div class="glass p-6 rounded-[2rem] mb-8 flex items-center justify-between">
            <div class="flex items-center space-x-4 flex-1">
                <div class="relative flex-1 max-w-md">
                    <i class="fas fa-search absolute left-5 top-1/2 -translate-y-1/2 text-slate-500"></i>
                    <input type="text" id="reportSearch" oninput="applyReportFilters()" placeholder="Search by phone number..."
                        class="w-full bg-white/5 border border-white/10 rounded-2xl py-3 pl-12 pr-5 text-xs text-white focus:outline-none focus:border-orange-500 transition">
                </div>
                <select id="statusFilter" onchange="applyReportFilters()" class="bg-white/5 border border-white/10 rounded-2xl py-3 px-5 text-xs text-white focus:outline-none focus:border-orange-500 transition">
                    <option value="all">All Status</option>
                    <option value="Pending">Pending</option>
                    <option value="Resolved">Resolved</option>
                    <option value="Dismissed">Dismissed</option>
                </select>
                <select id="categoryFilter" onchange="applyReportFilters()" class="bg-white/5 border border-white/10 rounded-2xl py-3 px-5 text-xs text-white focus:outline-none focus:border-orange-500 transition">
                    <option value="all">All Categories</option>
                    <option value="Abusive">Abusive</option>
                    <option value="Spam">Spam</option>
                    <option value="Fake">Fake Profile</option>
                </select>
            </div>
            <button onclick="loadReports()" class="w-10 h-10 glass rounded-xl flex items-center justify-center hover:text-orange-500 transition">
                <i class="fas fa-sync-alt text-xs"></i>
            </button>
        </div>
    `;

    const rows = reports.map(rep => {
        const isPending = rep.status === 'Pending';
        const categoryColor = getCategoryColor(rep.category);

        return `
            <tr class="hover:bg-white/[0.02] transition-colors group">
                <td class="p-6">
                    <div class="flex items-center space-x-3">
                        <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center text-xs font-bold text-slate-400 group-hover:bg-orange-500/20 group-hover:text-orange-500 transition">
                            <i class="fas fa-user-shield"></i>
                        </div>
                        <div onclick="openUserControl('${rep.reportedPhone}')" class="cursor-pointer group/target">
                            <p class="text-sm font-bold text-white group-hover/target:text-orange-500 transition-all underline underline-offset-4 decoration-white/10">${rep.reportedPhone}</p>
                            <p class="text-[9px] text-slate-500 uppercase font-black mt-1">Target Subject</p>
                        </div>
                    </div>
                </td>
                <td class="p-6">
                    ${UI.badge(rep.reportType || 'PROFILE', 'bg-blue-500/10 text-blue-400')}
                </td>
                <td class="p-6">
                    <div class="flex items-center space-x-2">
                        <div class="w-1.5 h-1.5 rounded-full ${categoryColor.dot}"></div>
                        <span class="text-xs font-bold ${categoryColor.text}">${rep.category}</span>
                    </div>
                </td>
                <td class="p-6">
                    <div onclick="openUserControl('${rep.reporterPhone}')" class="cursor-pointer group/reporter">
                        <p class="text-xs text-slate-300 font-bold group-hover/reporter:text-blue-400 transition-all underline underline-offset-4 decoration-white/10">${rep.reporterPhone}</p>
                        <p class="text-[9px] text-slate-500 uppercase font-black mt-1">Reporter</p>
                    </div>
                </td>
                <td class="p-6">
                    <span class="px-3 py-1 rounded-lg text-[9px] font-black uppercase ${getStatusStyle(rep.status)}">
                        ${rep.status}
                    </span>
                </td>
                <td class="p-6 text-right">
                    <div class="flex justify-end space-x-2">
                        <button onclick="viewReportDetails('${rep._id || rep.id}')" class="w-8 h-8 glass rounded-lg flex items-center justify-center text-[10px] hover:text-blue-400 transition" title="View Details"><i class="fas fa-eye"></i></button>
                        <button onclick="openUserControl('${rep.reportedPhone}')" class="px-4 py-2 glass rounded-xl text-[9px] font-black uppercase hover:bg-orange-500 hover:text-white transition shadow-lg hover:shadow-orange-500/20">Analyze</button>
                        ${isPending ? `
                            <button onclick="quickResolveReport('${rep._id}', 'Resolved')" class="w-8 h-8 bg-emerald-500/10 text-emerald-500 rounded-lg flex items-center justify-center text-[10px] hover:bg-emerald-500 hover:text-white transition" title="Mark Resolved"><i class="fas fa-check"></i></button>
                        ` : ''}
                    </div>
                </td>
            </tr>
        `;
    });

    mainContent.innerHTML = `
        <div class="animate-fade">
            ${statsHtml}
            ${filterHtml}
            ${UI.table(
                ['Target Subject', 'Type', 'Reason Category', 'Reporter', 'Status', 'Action'],
                rows
            )}
        </div>
    `;
}

function applyReportFilters() {
    const searchTerm = document.getElementById('reportSearch').value.toLowerCase();
    const statusFilter = document.getElementById('statusFilter').value;
    const categoryFilter = document.getElementById('categoryFilter').value;

    const filtered = allReports.filter(rep => {
        const matchesSearch = rep.reportedPhone.toLowerCase().includes(searchTerm) ||
                             rep.reporterPhone.toLowerCase().includes(searchTerm);
        const matchesStatus = statusFilter === 'all' || rep.status === statusFilter;
        const matchesCategory = categoryFilter === 'all' ||
                               (rep.category && rep.category.toLowerCase().includes(categoryFilter.toLowerCase()));

        return matchesSearch && matchesStatus && matchesCategory;
    });

    const tbody = document.querySelector('tbody');
    if (!tbody) return;

    const rows = filtered.map(rep => {
        const isPending = rep.status === 'Pending';
        const categoryColor = getCategoryColor(rep.category);

        return `
            <tr class="hover:bg-white/[0.02] transition-colors group">
                <td class="p-6">
                    <div class="flex items-center space-x-3">
                        <div class="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center text-xs font-bold text-slate-400 group-hover:bg-orange-500/20 group-hover:text-orange-500 transition">
                            <i class="fas fa-user-shield"></i>
                        </div>
                        <div onclick="openUserControl('${rep.reportedPhone}')" class="cursor-pointer group/target">
                            <p class="text-sm font-bold text-white group-hover/target:text-orange-500 transition-all underline underline-offset-4 decoration-white/10">${rep.reportedPhone}</p>
                            <p class="text-[9px] text-slate-500 uppercase font-black mt-1">Target Subject</p>
                        </div>
                    </div>
                </td>
                <td class="p-6">
                    ${UI.badge(rep.reportType || 'PROFILE', 'bg-blue-500/10 text-blue-400')}
                </td>
                <td class="p-6">
                    <div class="flex items-center space-x-2">
                        <div class="w-1.5 h-1.5 rounded-full ${categoryColor.dot}"></div>
                        <span class="text-xs font-bold ${categoryColor.text}">${rep.category}</span>
                    </div>
                </td>
                <td class="p-6">
                    <div onclick="openUserControl('${rep.reporterPhone}')" class="cursor-pointer group/reporter">
                        <p class="text-xs text-slate-300 font-bold group-hover/reporter:text-blue-400 transition-all underline underline-offset-4 decoration-white/10">${rep.reporterPhone}</p>
                        <p class="text-[9px] text-slate-500 uppercase font-black mt-1">Reporter</p>
                    </div>
                </td>
                <td class="p-6">
                    <span class="px-3 py-1 rounded-lg text-[9px] font-black uppercase ${getStatusStyle(rep.status)}">
                        ${rep.status}
                    </span>
                </td>
                <td class="p-6 text-right">
                    <div class="flex justify-end space-x-2">
                        <button onclick="viewReportDetails('${rep._id || rep.id}')" class="w-8 h-8 glass rounded-lg flex items-center justify-center text-[10px] hover:text-blue-400 transition" title="View Details"><i class="fas fa-eye"></i></button>
                        <button onclick="openUserControl('${rep.reportedPhone}')" class="px-4 py-2 glass rounded-xl text-[9px] font-black uppercase hover:bg-orange-500 hover:text-white transition shadow-lg hover:shadow-orange-500/20">Analyze</button>
                        ${isPending ? `
                            <button onclick="quickResolveReport('${rep._id}', 'Resolved')" class="w-8 h-8 bg-emerald-500/10 text-emerald-500 rounded-lg flex items-center justify-center text-[10px] hover:bg-emerald-500 hover:text-white transition" title="Mark Resolved"><i class="fas fa-check"></i></button>
                        ` : ''}
                    </div>
                </td>
            </tr>
        `;
    });

    tbody.innerHTML = filtered.length ? rows.join('') : '<tr><td colspan="6" class="p-20 text-center opacity-20 uppercase font-bold tracking-widest">No matching incidents found</td></tr>';
}

function getCategoryColor(category) {
    category = (category || '').toLowerCase();
    if (category.includes('abusive') || category.includes('harassment') || category.includes('galat')) {
        return { dot: 'bg-red-500', text: 'text-red-500' };
    }
    if (category.includes('spam') || category.includes('fake')) {
        return { dot: 'bg-orange-500', text: 'text-orange-500' };
    }
    return { dot: 'bg-blue-500', text: 'text-blue-400' };
}

function getStatusStyle(status) {
    switch(status) {
        case 'Pending': return 'bg-yellow-500/10 text-yellow-500 border border-yellow-500/20';
        case 'Resolved': return 'bg-emerald-500/10 text-emerald-500 border border-emerald-500/20';
        case 'Dismissed': return 'bg-slate-500/10 text-slate-400 border border-slate-500/20';
        default: return 'bg-white/5 text-slate-500';
    }
}

async function quickResolveReport(id, status) {
    try {
        await API.updateReportStatus(id, status);
        UI.showToast("Success", `Incident marked as ${status}`, "bg-emerald-500");
        loadReports();
    } catch (err) {
        UI.showToast("Error", err.message, "bg-red-500");
    }
}

async function viewReportDetails(id) {
    const report = allReports.find(r => (r._id || r.id) === id);
    if (!report) return;

    UI.modal.show(
        `
        <div class="flex items-center space-x-3">
            <div class="w-10 h-10 rounded-xl bg-red-500/20 text-red-500 flex items-center justify-center"><i class="fas fa-shield-alt"></i></div>
            <div>
                <h2 class="text-sm font-black text-white uppercase tracking-widest">Incident Details</h2>
                <p class="text-[10px] text-slate-500 font-bold uppercase">Report ID: ${id}</p>
            </div>
        </div>
        `,
        `
        <div class="grid grid-cols-2 gap-10">
            <div class="space-y-6">
                <div class="glass p-6 rounded-3xl">
                    <p class="text-[10px] font-black text-slate-500 uppercase mb-4 tracking-widest">Subject Information</p>
                    <div class="space-y-4">
                        <div onclick="openUserControl('${report.reportedPhone}')" class="flex justify-between items-center p-4 bg-white/5 rounded-2xl cursor-pointer hover:bg-orange-500/10 transition group/target">
                            <span class="text-[10px] font-bold text-slate-400">Target Phone</span>
                            <span class="text-sm font-black text-white group-hover/target:text-orange-500 transition-colors underline decoration-white/10">${report.reportedPhone}</span>
                        </div>
                        <div onclick="openUserControl('${report.reporterPhone}')" class="flex justify-between items-center p-4 bg-white/5 rounded-2xl cursor-pointer hover:bg-blue-500/10 transition group/reporter">
                            <span class="text-[10px] font-bold text-slate-400">Reporter Phone</span>
                            <span class="text-sm font-black text-white group-hover/reporter:text-blue-500 transition-colors underline decoration-white/10">${report.reporterPhone}</span>
                        </div>
                        <div class="flex justify-between items-center p-4 bg-white/5 rounded-2xl">
                            <span class="text-[10px] font-bold text-slate-400">Time Reported</span>
                            <span class="text-[10px] font-bold text-slate-300">${new Date(report.createdAt || report.timestamp).toLocaleString()}</span>
                        </div>
                    </div>
                </div>
            </div>
            <div class="space-y-6">
                <div class="glass p-6 rounded-3xl border-l-4 border-red-500">
                    <p class="text-[10px] font-black text-slate-500 uppercase mb-4 tracking-widest">Violation Report</p>
                    <div class="space-y-4">
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase mb-1">Category</p>
                            ${UI.badge(report.category, 'bg-red-500 text-white')}
                        </div>
                        <div>
                            <p class="text-[8px] font-black text-slate-500 uppercase mb-1">Reason / Description</p>
                            <p class="text-sm text-white font-medium italic">"${report.description || 'No detailed description provided by reporter.'}"</p>
                        </div>
                    </div>
                </div>

                <div class="flex space-x-4">
                    <button onclick="quickResolveReport('${report._id}', 'Resolved'); UI.modal.hide();" class="flex-1 py-4 bg-emerald-500 text-black font-black text-[10px] uppercase rounded-2xl hover:scale-105 transition">Mark as Resolved</button>
                    <button onclick="quickResolveReport('${report._id}', 'Dismissed'); UI.modal.hide();" class="flex-1 py-4 glass text-white font-black text-[10px] uppercase rounded-2xl hover:bg-white/10 transition">Dismiss Report</button>
                </div>
            </div>
        </div>
        `
    );
}
