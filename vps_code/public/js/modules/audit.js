async function loadAuditLogs() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "System Audit Trail";
    mainContent.innerHTML = UI.loader();

    try {
        const logs = await API.getAuditLogs();
        const rows = logs.map(l => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6">
                    <span class="px-3 py-1 bg-white/5 text-white text-[9px] font-black rounded-full uppercase border border-white/5">${l.action}</span>
                </td>
                <td class="p-6 text-sm font-bold text-orange-500">${l.target || 'System'}</td>
                <td class="p-6 text-xs text-slate-400 max-w-xs truncate">${l.details || '-'}</td>
                <td class="p-6 text-[10px] text-slate-500 font-bold uppercase">${new Date(l.timestamp).toLocaleString()}</td>
                <td class="p-6 text-right"><p class="text-[9px] font-black text-white">ADMIN: HIMANSHU</p></td>
            </tr>
        `);

        mainContent.innerHTML = UI.table(
            ['Action Type', 'Target Subject', 'Technical Details', 'Timestamp', 'Operator'],
            rows
        );
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing audit trail</p>`;
    }
}
