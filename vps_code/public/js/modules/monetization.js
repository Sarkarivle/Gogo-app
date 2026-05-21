async function loadMonetization() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Monetization Control Center";
    mainContent.innerHTML = UI.loader();

    try {
        const res = await fetch('/api/admin/config/razorpay_keys');
        const data = await res.json();
        const keys = data.config || { keyId: '', keySecret: '', planId: '' };

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade max-w-4xl mx-auto">
                <div class="grid grid-cols-3 gap-6">
                    ${UI.card('Gross Revenue', '₹0', 'Lifetime Earnings', 'text-emerald-500')}
                    ${UI.card('Active Plans', '0', 'Premium Subscriptions', 'text-blue-500')}
                    ${UI.card('Gateway Status', keys.keyId ? 'CONNECTED' : 'NOT LINKED', 'Razorpay Connectivity', keys.keyId ? 'text-emerald-500' : 'text-red-500')}
                </div>

                <div class="glass p-10 rounded-[3rem] space-y-8 border border-orange-500/10">
                    <div class="flex items-center justify-between border-b border-white/5 pb-6">
                        <div>
                            <h3 class="text-xl font-black text-white uppercase">Razorpay Integration</h3>
                            <p class="text-[10px] text-slate-500 mt-1 uppercase font-bold">Manage your production payment gateway credentials</p>
                        </div>
                        <img src="https://razorpay.com/favicon.png" class="w-8 h-8 opacity-50" alt="RP">
                    </div>

                    <div class="space-y-6">
                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">API Key ID</label>
                            <input type="text" id="rp_key_id" value="${keys.keyId || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm text-white focus:border-orange-500/50">
                        </div>

                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">API Key Secret</label>
                            <input type="password" id="rp_key_secret" value="${keys.keySecret || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm text-white focus:border-orange-500/50">
                        </div>

                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Razorpay Plan ID (Monthly)</label>
                            <input type="text" id="rp_plan_id" value="${keys.planId || ''}" placeholder="plan_..." class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-sm text-white focus:border-orange-500/50">
                        </div>

                        <div class="pt-4">
                            <button onclick="saveRazorpayKeys()" class="w-full py-5 bg-orange-500 text-black rounded-2xl text-[11px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-orange-500/20">
                                Synchronize Gateway & Plan
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;
    } catch (err) {
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 font-black uppercase">Error</p>`;
    }
}

async function saveRazorpayKeys() {
    const keyId = document.getElementById('rp_key_id').value;
    const keySecret = document.getElementById('rp_key_secret').value;
    const planId = document.getElementById('rp_plan_id').value;

    if (!keyId || !keySecret || !planId) return alert("All fields required");

    try {
        await fetch('/api/admin/config/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key: 'razorpay_keys', value: { keyId, keySecret, planId } })
        });
        alert("Saved Successfully");
        loadMonetization();
    } catch (err) { alert("Error saving config"); }
}
