async function loadAuditLogs() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "System Audit Trail";
    mainContent.innerHTML = UI.skeletonTable(15);

    try {
        const logs = await API.getAuditLogs();
        if (!Array.isArray(logs)) throw new Error("Invalid response format");

        const rows = logs.map(l => {
            const isPhone = l.target && /^\d{10,}$/.test(l.target.replace(/\+/g, ''));
            return `
                <tr class="hover:bg-white/[0.01]">
                    <td class="p-6">
                        <span class="px-3 py-1 bg-white/5 text-white text-[9px] font-black rounded-full uppercase border border-white/5">${l.action || 'Unknown'}</span>
                    </td>
                    <td class="p-6 text-sm font-bold text-orange-500">
                        ${isPhone ? `<span onclick="openUserControl('${l.target}')" class="cursor-pointer hover:underline underline-offset-4 decoration-white/20 transition-all">${l.target}</span>` : (l.target || 'System')}
                    </td>
                    <td class="p-6 text-xs text-slate-400 max-w-xs truncate">${l.details || '-'}</td>
                    <td class="p-6 text-[10px] text-slate-500 font-bold uppercase">${window.formatDateTime(l.timestamp)}</td>
                    <td class="p-6 text-right"><p class="text-[9px] font-black text-white uppercase">ADMIN: ${l.adminName || 'STAFF'}</p></td>
                </tr>
            `;
        });

        mainContent.innerHTML = UI.table(
            ['Action Type', 'Target Subject', 'Technical Details', 'Timestamp', 'Operator'],
            rows
        );
    } catch (err) {
        console.error("Audit Logs Error:", err);
        mainContent.innerHTML = `
            <div class="p-20 text-center space-y-4">
                <p class="text-red-500 font-bold uppercase tracking-widest">Error synchronizing audit trail</p>
                <p class="text-[10px] text-slate-500 font-black uppercase">${err.message}</p>
                <button onclick="loadAuditLogs()" class="px-6 py-2 glass rounded-xl text-[10px] font-black uppercase">Retry Sync</button>
            </div>
        `;
    }
}
