async function loadReports() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Security Incidents";
    mainContent.innerHTML = UI.loader();

    try {
        const reports = await API.getReports();
        const rows = reports.map(rep => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6"><p class="text-sm font-bold text-white">${rep.reportedPhone}</p></td>
                <td class="p-6">${UI.badge(rep.reportType || 'PROFILE', 'bg-orange-500/10 text-orange-500')}</td>
                <td class="p-6">${UI.badge(rep.category, 'bg-red-500/10 text-red-500')}</td>
                <td class="p-6 text-xs text-slate-400 font-bold">${rep.reporterPhone}</td>
                <td class="p-6">
                    <span class="px-3 py-1 rounded-full text-[8px] font-black uppercase ${rep.status === 'Pending' ? 'bg-yellow-500/10 text-yellow-500' : 'bg-emerald-500/10 text-emerald-500'}">
                        ${rep.status}
                    </span>
                </td>
                <td class="p-6 text-right">
                    <button onclick="openUserControl('${rep.reportedPhone}')" class="px-4 py-2 glass rounded-xl text-[9px] font-black uppercase hover:bg-white/10 transition">Analyze Subject</button>
                </td>
            </tr>
        `);

        mainContent.innerHTML = UI.table(
            ['Target Subject', 'Type', 'Reason Category', 'Reporter', 'Status', 'Action'],
            rows
        );
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing security feed</p>`;
    }
}
