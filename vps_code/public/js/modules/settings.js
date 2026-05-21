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
            { id: 'about_us', name: 'About Us' }
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

async function loadSupportMessages() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Support Channels";
    mainContent.innerHTML = UI.loader();

    try {
        const messages = await API.getSupportMessages();
        const rows = messages.map(m => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6 font-bold text-white text-xs">${m.name}</td>
                <td class="p-6">
                    ${UI.badge(m.status, m.status === 'Resolved' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-red-500/10 text-red-500')}
                </td>
                <td class="p-6 text-[10px] text-slate-500 font-bold uppercase">${new Date(m.createdAt).toLocaleString()}</td>
                <td class="p-6 text-right">
                    <button onclick="viewSupportMessage('${m._id}')" class="px-4 py-2 glass rounded-xl text-[9px] font-black uppercase hover:bg-white/10 transition">Interact</button>
                </td>
            </tr>
        `);

        mainContent.innerHTML = UI.table(
            ['User', 'Status', 'Timestamp', 'Action'],
            rows
        );
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing support queue</p>`;
    }
}
