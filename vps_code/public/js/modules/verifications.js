async function loadVerifications() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Identity Verification Center";
    mainContent.innerHTML = UI.skeletonGrid(6);

    try {
        const reqs = await API.getVerificationRequests();
        mainContent.innerHTML = `
            <div class="grid grid-cols-2 gap-8 animate-fade">
                ${reqs.map(req => `
                    <div class="glass p-8 rounded-[3rem] flex flex-col space-y-6 border border-white/5 hover:border-blue-500/20 transition relative group">
                        <!-- Header -->
                        <div class="flex justify-between items-start">
                            <div class="flex items-center space-x-4">
                                <div class="w-12 h-12 rounded-2xl bg-blue-500/20 flex items-center justify-center text-blue-500 font-black text-xl">
                                    ${req.userName ? req.userName[0] : '?'}
                                </div>
                                <div>
                                    <h4 class="text-base font-black text-white uppercase">${req.userName || 'Anonymous'}</h4>
                                    <p class="text-[10px] text-slate-500 font-bold">${req.userPhone}</p>
                                </div>
                            </div>
                            <div class="text-right">
                                ${UI.badge('PENDING REVIEW', 'bg-blue-500/10 text-blue-500')}
                                <p class="text-[8px] text-slate-500 mt-2 uppercase font-black">${new Date(req.submittedAt).toLocaleString()}</p>
                            </div>
                        </div>

                        <!-- Comparison Logic -->
                        <div class="grid grid-cols-2 gap-4">
                            <!-- Verification Selfie -->
                            <div class="space-y-2">
                                <p class="text-[9px] font-black text-slate-500 uppercase tracking-widest text-center">Verification Selfie</p>
                                <div class="rounded-[2rem] overflow-hidden border-2 border-blue-500/30 bg-black/40 aspect-[3/4] relative group/img">
                                    <img src="${API.getAuthUrl(req.selfieUrl)}" class="w-full h-full object-cover" alt="Selfie">
                                    <div class="absolute inset-0 bg-black/60 opacity-0 group-hover/img:opacity-100 transition flex items-center justify-center">
                                        <button onclick="window.open('${API.getAuthUrl(req.selfieUrl)}')" class="w-12 h-12 glass rounded-full flex items-center justify-center text-white hover:bg-white/20">
                                            <i class="fas fa-expand"></i>
                                        </button>
                                    </div>
                                </div>
                            </div>

                            <!-- Current Profile Pic -->
                            <div class="space-y-2">
                                <p class="text-[9px] font-black text-slate-500 uppercase tracking-widest text-center">Current Profile Pic</p>
                                <div class="rounded-[2rem] overflow-hidden border-2 border-white/10 bg-black/40 aspect-[3/4] relative group/img">
                                    <img src="${req.profileImage ? API.getAuthUrl(req.profileImage) : 'https://placehold.co/400x600?text=No+Profile+Pic'}" class="w-full h-full object-cover" alt="Profile">
                                    <div class="absolute inset-0 bg-black/60 opacity-0 group-hover/img:opacity-100 transition flex items-center justify-center">
                                        <button onclick="window.open('${req.profileImage ? API.getAuthUrl(req.profileImage) : '#'}')" class="w-12 h-12 glass rounded-full flex items-center justify-center text-white hover:bg-white/20">
                                            <i class="fas fa-expand"></i>
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- Actions -->
                        <div class="flex space-x-3 pt-4 border-t border-white/5">
                            <button onclick="approveVerification('${req.userPhone}')" class="flex-[2] py-4 bg-gradient-to-r from-blue-500 to-blue-600 text-white rounded-2xl text-xs font-black uppercase hover:scale-[1.02] active:scale-[0.98] transition shadow-lg shadow-blue-500/20">
                                <i class="fas fa-check-double mr-2"></i> Approve Identity
                            </button>
                            <button onclick="rejectVerificationPrompt('${req.userPhone}')" class="flex-1 py-4 bg-red-500/10 text-red-500 border border-red-500/20 rounded-2xl text-xs font-black uppercase hover:bg-red-500 hover:text-white transition">
                                <i class="fas fa-times mr-1"></i> Reject
                            </button>
                            <button onclick="openUserControl('${req.userPhone}')" class="px-5 py-4 glass rounded-2xl text-slate-400 hover:text-white hover:bg-white/5 transition">
                                <i class="fas fa-user-shield"></i>
                            </button>
                        </div>
                    </div>
                `).join('') || `
                    <div class="col-span-2 py-40 flex flex-col items-center justify-center glass rounded-[3rem] border-2 border-dashed border-white/5 opacity-30">
                        <i class="fas fa-user-check text-6xl mb-6"></i>
                        <p class="uppercase font-black tracking-[0.3em] text-xl">Inbox Cleared: No Pending Requests</p>
                    </div>
                `}
            </div>
        `;
    } catch (err) {
        console.error("Verification Feed Error:", err);
        mainContent.innerHTML = `<div class="p-20 text-center"><p class="text-red-500 uppercase font-black">Error syncing identity feed</p></div>`;
    }
}

async function approveVerification(phone) {
    if (!confirm(`Are you sure you want to verify ${phone} and grant the Blue Tick?`)) return;

    try {
        const res = await API.approveVerification(phone);
        if (res.success) {
            UI.showToast("Success", "User verified successfully", "bg-emerald-500");
            loadVerifications();
        }
    } catch (err) {
        UI.showToast("Error", "Failed to approve verification", "bg-red-500");
    }
}

async function rejectVerificationPrompt(phone) {
    const reason = prompt("Enter rejection reason (User will be notified):", "Profile image doesn't match selfie.");
    if (reason === null) return;

    try {
        const res = await API.rejectVerification(phone, { reason });
        if (res.success) {
            UI.showToast("Rejected", "Verification request denied", "bg-orange-500");
            loadVerifications();
        }
    } catch (err) {
        UI.showToast("Error", "Action failed", "bg-red-500");
    }
}
