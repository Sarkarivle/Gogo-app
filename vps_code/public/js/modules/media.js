let currentMediaFilter = 'all';
let reportedOnlyFilter = false;

async function loadMedia(filter = 'all', reportedOnly = false) {
    currentMediaFilter = filter;
    reportedOnlyFilter = reportedOnly;

    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Media Governance & Privacy Vault";
    mainContent.innerHTML = UI.loader();

    try {
        const data = await API.getAllMedia(filter, reportedOnly);

        if (!data.success) throw new Error("Failed to fetch media");

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade pb-20">
                <div class="glass p-10 rounded-[3rem] border border-orange-500/10">
                    <!-- Governance Header -->
                    <div class="flex items-center justify-between border-b border-white/5 pb-6 mb-8">
                        <div>
                            <h3 class="text-xl font-black text-white uppercase tracking-tight">User Generated Content</h3>
                            <p class="text-[10px] text-slate-500 mt-1 uppercase font-bold tracking-widest">
                                ${reportedOnly ? 'Moderating Reported Assets' : `Reviewing ${data.media.length} global assets`}
                            </p>
                        </div>
                        <div class="flex gap-4">
                            <!-- Quick Filters -->
                            <div class="flex bg-white/5 p-1 rounded-2xl border border-white/5">
                                ${['all', 'Profile', 'Chat'].map(f => `
                                    <button onclick="loadMedia('${f}', ${reportedOnlyFilter})" class="px-4 py-2 rounded-xl text-[8px] font-black uppercase transition ${currentMediaFilter === f ? 'bg-orange-500 text-black' : 'text-slate-500 hover:text-white'}">
                                        ${f}
                                    </button>
                                `).join('')}
                            </div>

                            <!-- Reported Only Toggle -->
                            <button onclick="loadMedia('${currentMediaFilter}', ${!reportedOnlyFilter})" class="px-6 py-2 rounded-2xl text-[8px] font-black uppercase transition border-2 ${reportedOnlyFilter ? 'border-red-500 bg-red-500/10 text-red-500' : 'border-white/10 text-slate-500'}">
                                <i class="fas fa-shield-halved mr-2"></i> Reported Only
                            </button>

                            <button onclick="loadMedia(currentMediaFilter, reportedOnlyFilter)" class="w-10 h-10 glass rounded-xl text-white text-[10px] flex items-center justify-center transition hover:bg-white/10">
                                <i class="fas fa-sync-alt"></i>
                            </button>
                        </div>
                    </div>

                    <!-- Media Grid -->
                    <div class="grid grid-cols-5 gap-6">
                        ${data.media.map((m, i) => `
                            <div class="group relative aspect-square bg-black/60 rounded-[2.5rem] overflow-hidden border border-white/5 hover:border-orange-500/30 transition-all shadow-2xl">
                                <!-- Blur Container -->
                                <div class="absolute inset-0 z-10 flex items-center justify-center backdrop-blur-3xl bg-black/40 group-hover:bg-black/20 transition-all media-blur-layer" id="blur-${i}">
                                    <button onclick="revealMedia(${i})" class="px-4 py-2 bg-white/10 hover:bg-white/20 border border-white/10 rounded-full text-[8px] font-black text-white uppercase tracking-tighter transition-all transform group-hover:scale-110">
                                        <i class="fas fa-eye mr-2"></i> Reveal Content
                                    </button>
                                </div>

                                <img src="${m.url}" class="w-full h-full object-cover" onerror="this.src='https://placehold.co/400x400/111/white?text=Media+Missing'">

                                <!-- Governance Overlay -->
                                <div class="absolute inset-0 z-20 bg-gradient-to-t from-black via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-all duration-300 p-6 flex flex-col justify-end">
                                    <div class="space-y-1 mb-4">
                                        <p class="text-[9px] font-black text-white truncate">${m.ownerName || m.owner}</p>
                                        <p class="text-[7px] font-bold text-orange-500 uppercase">${m.type} • ${new Date(m.timestamp).toLocaleDateString()}</p>
                                    </div>
                                    <div class="flex gap-2">
                                        <button onclick="deleteMedia('${m.url}', '${m.type}', '${m.owner}')" class="flex-1 py-3 bg-red-500/80 hover:bg-red-500 text-white text-[9px] font-black rounded-xl uppercase transition">Purge</button>
                                        <button onclick="window.open('${m.url}', '_blank')" class="w-10 py-3 bg-white/10 text-white text-[10px] font-black rounded-xl hover:bg-white/20 transition flex items-center justify-center"><i class="fas fa-external-link-alt"></i></button>
                                    </div>
                                </div>

                                <!-- Privacy Badge -->
                                <div class="absolute top-4 left-4 z-30 px-3 py-1 bg-black/60 backdrop-blur-md rounded-lg text-[7px] font-black uppercase border border-white/5 ${m.type === 'Profile' ? 'text-blue-400' : 'text-emerald-400'}">
                                    ${m.type}
                                </div>
                            </div>
                        `).join('')}
                    </div>

                    ${data.media.length === 0 ? `
                        <div class="p-40 text-center flex flex-col items-center justify-center space-y-6">
                            <i class="fas fa-shield-check text-5xl text-emerald-500/20"></i>
                            <div class="space-y-1">
                                <p class="opacity-20 uppercase font-black tracking-[0.5em] text-sm">Clean Infrastructure</p>
                                <p class="text-[10px] text-slate-500 uppercase font-bold">No assets found matching current filtration</p>
                            </div>
                        </div>
                    ` : ''}
                </div>

                <!-- Privacy & Ethics Notice -->
                <div class="max-w-2xl mx-auto glass p-6 rounded-2xl border border-white/5 flex items-start gap-4">
                    <i class="fas fa-user-shield text-orange-500 mt-1"></i>
                    <div>
                        <h4 class="text-[10px] font-black text-white uppercase tracking-wider">Professional Conduct Note</h4>
                        <p class="text-[9px] text-slate-500 font-bold uppercase leading-relaxed mt-1">
                            Media assets are blurred by default to maintain professional boundaries. Access private media only for moderation purposes (Terms 4.2).
                            Purging media permanently erases the asset from VPS storage and database pointers.
                        </p>
                    </div>
                </div>
            </div>
        `;
    } catch (err) {
        console.error(err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 font-black uppercase">Telemetry Synchronization Failure</p>`;
    }
}

function revealMedia(index) {
    const layer = document.getElementById(`blur-${index}`);
    if (layer) {
        layer.classList.add('hidden');
    }
}

async function deleteMedia(url, type, owner) {
    if (!confirm("Are you certain you want to purge this media from the server? This action is irreversible.")) return;

    try {
        const data = await API.deleteMedia({ url, type, owner });
        if (data.success) loadMedia(currentMediaFilter, reportedOnlyFilter);
        else alert("Purge failed");
    } catch (e) {
        alert("Server communication error");
    }
}
