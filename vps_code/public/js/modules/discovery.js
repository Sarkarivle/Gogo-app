// Discovery & Feed Control Module

async function loadDiscovery() {
    console.log("🔭 Loading Discovery Controls UI...");
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');

    if (!modTitle || !mainContent) return;

    modTitle.innerText = "Discovery & Feed Controls";

    // Show Skeleton Loading
    mainContent.innerHTML = `
        <div class="space-y-10 animate-fade">
            <div class="grid grid-cols-3 gap-6">${UI.skeletonCard()} ${UI.skeletonCard()} ${UI.skeletonCard()}</div>
            <div class="glass p-10 rounded-[3rem] h-96 skeleton"></div>
        </div>
    `;

    try {
        const res = await API.getFeatureFlags();

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade">
                <div class="grid grid-cols-3 gap-6">
                    <div class="glass p-8 rounded-[2.5rem] border-l-4 border-orange-500">
                        <p class="text-[10px] font-black text-slate-500 uppercase mb-2">Feed Mode</p>
                        <h2 class="text-2xl font-black text-white uppercase">Engagement</h2>
                    </div>
                    <div class="glass p-8 rounded-[2.5rem] border-l-4 border-emerald-500">
                        <p class="text-[10px] font-black text-slate-500 uppercase mb-2">Reach</p>
                        <h2 class="text-2xl font-black text-white uppercase">Global</h2>
                    </div>
                    <div class="glass p-8 rounded-[2.5rem] border-l-4 border-blue-500">
                        <p class="text-[10px] font-black text-slate-500 uppercase mb-2">Safety</p>
                        <h2 class="text-2xl font-black text-white uppercase">Active</h2>
                    </div>
                </div>

                <div class="grid grid-cols-12 gap-10">
                    <div class="col-span-5 glass p-10 rounded-[3rem] space-y-8">
                        <h4 class="text-xs font-black text-white uppercase border-b border-white/5 pb-4">Algorithm Settings</h4>
                        <div class="space-y-6">
                            ${renderDiscoveryToggle('Boost Verified', 'boost_verified', true)}
                            ${renderDiscoveryToggle('New User Priority', 'boost_new', true)}
                            ${renderDiscoveryToggle('Strict Location', 'geo_strict', false)}
                        </div>
                    </div>
                    <div class="col-span-7 glass p-10 rounded-[3rem]">
                        <h4 class="text-xs font-black text-white uppercase border-b border-white/5 pb-4 mb-6">Discovery Radius</h4>
                        <div class="space-y-6">
                            <input type="range" class="w-full accent-orange-500" min="10" max="500" value="100">
                            <button onclick="showSystemToast('Success', 'Discovery Radius Updated', 'bg-emerald-500')" class="w-full py-4 bg-orange-500 text-black rounded-2xl text-[10px] font-black uppercase">Save Parameters</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
    } catch (err) {
        console.error("Discovery UI Fail:", err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 font-bold uppercase">Sync Failed</p>`;
    }
}

function renderDiscoveryToggle(label, key, active) {
    return `
        <div class="flex justify-between items-center">
            <span class="text-[10px] font-bold text-slate-400 uppercase">${label}</span>
            <button onclick="this.querySelector('span').classList.toggle('translate-x-6'); this.classList.toggle('bg-orange-500'); this.classList.toggle('bg-white/10')" class="relative inline-flex h-5 w-10 items-center rounded-full transition-colors ${active ? 'bg-orange-500' : 'bg-white/10'}">
                <span class="inline-block h-3 w-3 transform rounded-full bg-white transition-transform ${active ? 'translate-x-6' : 'translate-x-1'}"></span>
            </button>
        </div>
    `;
}
