async function loadVerifications() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Identity Verification Center";
    mainContent.innerHTML = UI.loader();

    try {
        const reqs = await API.getVerificationRequests();
        mainContent.innerHTML = `
            <div class="grid grid-cols-3 gap-6 animate-fade">
                ${reqs.map(req => `
                    <div class="glass p-6 rounded-[2rem] flex flex-col space-y-4 border border-white/5 hover:border-blue-500/30 transition">
                        <div class="flex justify-between items-start">
                            <div>
                                <p class="text-xs font-bold text-white">${req.userPhone}</p>
                                <p class="text-[10px] text-slate-500 uppercase font-black tracking-tighter">${new Date(req.submittedAt).toLocaleString()}</p>
                            </div>
                            ${UI.badge('PENDING', 'bg-blue-500/10 text-blue-500')}
                        </div>
                        <div class="flex-1 rounded-2xl overflow-hidden border border-white/5 bg-black/20 group relative">
                            <img src="${req.selfieUrl}" class="w-full h-64 object-cover transition duration-500 group-hover:scale-110" alt="Selfie">
                            <div class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition flex items-center justify-center">
                                <a href="${req.selfieUrl}" target="_blank" class="glass p-4 rounded-full text-white hover:bg-white/20"><i class="fas fa-expand"></i></a>
                            </div>
                        </div>
                        <div class="flex space-x-2">
                            <button onclick="approveVerification('${req.userPhone}')" class="flex-1 py-3 bg-blue-500 text-white rounded-xl text-[10px] font-black uppercase hover:bg-blue-600 transition shadow-lg shadow-blue-500/20">Approve & Verify</button>
                            <button onclick="openUserControl('${req.userPhone}')" class="px-4 py-3 glass rounded-xl text-white hover:bg-white/10 transition"><i class="fas fa-user"></i></button>
                        </div>
                    </div>
                `).join('') || '<div class="col-span-3 py-40 text-center glass rounded-[3rem] opacity-30 font-black uppercase tracking-widest text-xl">No pending identity requests</div>'}
            </div>
        `;
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 uppercase font-black">Error synchronizing identity feed</p>`;
    }
}

async function approveVerification(phone) {
    if (!confirm("Approve verification for " + phone + "?")) return;
    try {
        await API.approveVerification(phone);
        alert("Identity Verified Successfully");
        loadVerifications();
    } catch (err) {
        alert("Failed to approve verification");
    }
}
