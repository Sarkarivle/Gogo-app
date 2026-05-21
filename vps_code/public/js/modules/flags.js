async function loadFeatureFlags() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "System Feature Toggles";
    mainContent.innerHTML = UI.loader();

    try {
        const res = await fetch('/api/admin/feature-flags');
        const flags = await res.json();

        const rows = flags.map(f => `
            <tr class="hover:bg-white/[0.01]">
                <td class="p-6">
                    <p class="text-sm font-bold text-white">${f.name}</p>
                    <p class="text-[10px] text-slate-500 font-mono">${f.key}</p>
                </td>
                <td class="p-6 text-xs text-slate-400 font-medium">${f.description || 'No description'}</td>
                <td class="p-6">
                    <button onclick="toggleFlag('${f.key}', ${!f.isEnabled})" class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus:outline-none ${f.isEnabled ? 'bg-orange-500' : 'bg-slate-700'}">
                        <span class="inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${f.isEnabled ? 'translate-x-6' : 'translate-x-1'}"></span>
                    </button>
                </td>
                <td class="p-6 text-right">
                    <span class="text-[9px] text-slate-500 uppercase font-black">Last Sync: ${new Date(f.updatedAt).toLocaleDateString()}</span>
                </td>
            </tr>
        `);

        mainContent.innerHTML = `
            <div class="space-y-6">
                <div class="flex justify-between items-center bg-orange-500/5 p-6 rounded-[2rem] border border-orange-500/10">
                    <div>
                        <h4 class="text-white font-black uppercase text-xs">Runtime Configuration</h4>
                        <p class="text-[10px] text-slate-500 mt-1 uppercase">Changes take effect immediately on next app session or socket heartbeat</p>
                    </div>
                    <button onclick="addNewFlag()" class="px-6 py-3 bg-orange-500 text-black rounded-xl text-[10px] font-black uppercase">Add New Flag</button>
                </div>
                ${UI.table(['Feature Name', 'Description', 'Status', 'Registry Info'], rows)}
            </div>
        `;
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing feature registry</p>`;
    }
}

async function toggleFlag(key, isEnabled) {
    try {
        await fetch('/api/admin/feature-flags/toggle', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ key, isEnabled })
        });
        loadFeatureFlags();
    } catch (e) { alert("Failed to toggle flag"); }
}

function addNewFlag() {
    // Modal for adding a new flag
    UI.modal.show(
        '<p class="text-white font-black uppercase">Create Deployment Flag</p>',
        `
        <div class="space-y-6">
            <input type="text" id="newFlagName" placeholder="Display Name" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm focus:border-orange-500">
            <input type="text" id="newFlagKey" placeholder="technical_key_slug" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm font-mono focus:border-orange-500">
            <textarea id="newFlagDesc" placeholder="Description of the feature..." class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm h-32 focus:border-orange-500"></textarea>
            <button onclick="saveNewFlag()" class="w-full py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase">Deploy Flag</button>
        </div>
        `
    );
}

async function saveNewFlag() {
    const name = document.getElementById('newFlagName').value;
    const key = document.getElementById('newFlagKey').value;
    const description = document.getElementById('newFlagDesc').value;
    if (!name || !key) return alert("Required fields missing");

    await fetch('/api/admin/feature-flags/toggle', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({ name, key, description, isEnabled: false })
    });
    UI.modal.hide();
    loadFeatureFlags();
}
