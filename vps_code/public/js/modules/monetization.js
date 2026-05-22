async function loadMonetization() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Monetization Control Center";
    mainContent.innerHTML = UI.loader();

    try {
        const res = await fetch('/api/admin/config/payment_settings');
        const data = await res.json();

        let settings = data.config || {};

        // Ensure default structure
        if (!settings.activeGateway) {
            settings.activeGateway = 'razorpay';
        }

        if (!settings.razorpay) settings.razorpay = { keyId: '', keySecret: '', planId: '', webhookSecret: '' };
        if (!settings.phonepe) settings.phonepe = { merchantId: '', saltKey: '', saltIndex: '1', env: 'UAT', webhookSecret: '' };
        if (!settings.cashfree) settings.cashfree = { appId: '', secretKey: '', env: 'SANDBOX', webhookSecret: '' };

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade max-w-4xl mx-auto pb-20">
                <div class="grid grid-cols-3 gap-6">
                    ${UI.card('Gross Revenue', '₹0', 'Lifetime Earnings', 'text-emerald-500')}
                    ${UI.card('Active Plans', '0', 'Premium Subscriptions', 'text-blue-500')}
                    ${UI.card('Active Gateway', (settings.activeGateway || 'razorpay').toUpperCase(), 'Current System', 'text-orange-500')}
                </div>

                <div class="glass p-10 rounded-[3rem] space-y-8 border border-orange-500/10">
                    <div class="flex items-center justify-between border-b border-white/5 pb-6">
                        <div>
                            <h3 class="text-xl font-black text-white uppercase">Payment Gateway Selector</h3>
                            <p class="text-[10px] text-slate-500 mt-1 uppercase font-bold">Switch between providers instantly</p>
                        </div>
                    </div>

                    <div class="flex gap-4">
                        <button onclick="toggleGateway('razorpay')" class="flex-1 py-4 rounded-2xl border-2 ${settings.activeGateway === 'razorpay' ? 'border-orange-500 bg-orange-500/10' : 'border-white/5 bg-white/5'} transition">
                            <span class="text-xs font-black uppercase ${settings.activeGateway === 'razorpay' ? 'text-orange-500' : 'text-slate-500'}">Razorpay</span>
                        </button>
                        <button onclick="toggleGateway('phonepe')" class="flex-1 py-4 rounded-2xl border-2 ${settings.activeGateway === 'phonepe' ? 'border-purple-500 bg-purple-500/10' : 'border-white/5 bg-white/5'} transition">
                            <span class="text-xs font-black uppercase ${settings.activeGateway === 'phonepe' ? 'text-purple-500' : 'text-slate-500'}">PhonePe</span>
                        </button>
                        <button onclick="toggleGateway('cashfree')" class="flex-1 py-4 rounded-2xl border-2 ${settings.activeGateway === 'cashfree' ? 'border-blue-500 bg-blue-500/10' : 'border-white/5 bg-white/5'} transition">
                            <span class="text-xs font-black uppercase ${settings.activeGateway === 'cashfree' ? 'text-blue-500' : 'text-slate-500'}">Cashfree</span>
                        </button>
                    </div>
                </div>

                <div id="gatewayConfigs" class="grid grid-cols-1 gap-8">
                    <!-- Razorpay Config -->
                    <div class="glass p-8 rounded-[2rem] space-y-6 ${settings.activeGateway === 'razorpay' ? 'ring-2 ring-orange-500/30' : 'opacity-40 grayscale'} transition-all">
                        <div class="flex items-center justify-between border-b border-white/5 pb-4">
                            <h4 class="text-sm font-black text-white uppercase">Razorpay Settings</h4>
                            <img src="https://razorpay.com/favicon.png" class="w-6 h-6" alt="RP">
                        </div>
                        <div class="grid grid-cols-2 gap-4">
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Key ID</label>
                                <input type="text" id="rp_key_id" value="${settings.razorpay?.keyId || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Key Secret</label>
                                <input type="password" id="rp_key_secret" value="${settings.razorpay?.keySecret || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                        </div>
                        <div class="grid grid-cols-2 gap-4">
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Subscription Plan ID</label>
                                <input type="text" id="rp_plan_id" value="${settings.razorpay?.planId || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Webhook Secret</label>
                                <input type="password" id="rp_webhook_secret" value="${settings.razorpay?.webhookSecret || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                        </div>
                    </div>

                    <!-- PhonePe Config -->
                    <div class="glass p-8 rounded-[2rem] space-y-6 ${settings.activeGateway === 'phonepe' ? 'ring-2 ring-purple-500/30' : 'opacity-40 grayscale'} transition-all">
                        <div class="flex items-center justify-between border-b border-white/5 pb-4">
                            <h4 class="text-sm font-black text-white uppercase">PhonePe Settings</h4>
                            <i class="fab fa-product-hunt text-purple-500"></i>
                        </div>
                        <div class="grid grid-cols-2 gap-4">
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Merchant ID</label>
                                <input type="text" id="pp_merchant_id" value="${settings.phonepe?.merchantId || ''}" placeholder="M22TH..." class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Salt Key</label>
                                <input type="password" id="pp_salt_key" value="${settings.phonepe?.saltKey || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                        </div>
                        <div class="grid grid-cols-3 gap-4">
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Salt Index</label>
                                <input type="text" id="pp_salt_index" value="${settings.phonepe?.saltIndex || '1'}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Environment</label>
                                <select id="pp_env" class="w-full bg-[#12151f] border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                                    <option value="UAT" ${settings.phonepe?.env === 'UAT' ? 'selected' : ''}>UAT (Testing)</option>
                                    <option value="PROD" ${settings.phonepe?.env === 'PROD' ? 'selected' : ''}>PROD (Production)</option>
                                </select>
                            </div>
                             <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Webhook Secret</label>
                                <input type="password" id="pp_webhook_secret" value="${settings.phonepe?.webhookSecret || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                        </div>
                    </div>

                    <!-- Cashfree Config -->
                    <div class="glass p-8 rounded-[2rem] space-y-6 ${settings.activeGateway === 'cashfree' ? 'ring-2 ring-blue-500/30' : 'opacity-40 grayscale'} transition-all">
                        <div class="flex items-center justify-between border-b border-white/5 pb-4">
                            <h4 class="text-sm font-black text-white uppercase">Cashfree Settings</h4>
                            <i class="fas fa-money-bill-transfer text-blue-500"></i>
                        </div>
                        <div class="grid grid-cols-2 gap-4">
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">App ID</label>
                                <input type="text" id="cf_app_id" value="${settings.cashfree?.appId || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Secret Key</label>
                                <input type="password" id="cf_secret_key" value="${settings.cashfree?.secretKey || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                        </div>
                        <div class="grid grid-cols-2 gap-4">
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Environment</label>
                                <select id="cf_env" class="w-full bg-[#12151f] border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                                    <option value="SANDBOX" ${settings.cashfree?.env === 'SANDBOX' ? 'selected' : ''}>SANDBOX (Testing)</option>
                                    <option value="PROD" ${settings.cashfree?.env === 'PROD' ? 'selected' : ''}>PROD (Production)</option>
                                </select>
                            </div>
                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Webhook Secret</label>
                                <input type="password" id="cf_webhook_secret" value="${settings.cashfree?.webhookSecret || ''}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                            </div>
                        </div>
                    </div>
                </div>

                <div class="pt-4">
                    <button onclick="savePaymentSettings('${settings.activeGateway}')" class="w-full py-5 bg-orange-500 text-black rounded-2xl text-[11px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-orange-500/20">
                        Sync Payment Infrastructure
                    </button>
                </div>
            </div>
        `;
    } catch (err) {
        console.error(err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 font-black uppercase">Error Loading Monetization</p>`;
    }
}

async function toggleGateway(gateway) {
    savePaymentSettings(gateway);
}

async function savePaymentSettings(activeGateway) {
    const settings = {
        activeGateway: activeGateway,
        razorpay: {
            keyId: document.getElementById('rp_key_id').value,
            keySecret: document.getElementById('rp_key_secret').value,
            planId: document.getElementById('rp_plan_id').value,
            webhookSecret: document.getElementById('rp_webhook_secret').value
        },
        phonepe: {
            merchantId: document.getElementById('pp_merchant_id').value,
            saltKey: document.getElementById('pp_salt_key').value,
            saltIndex: document.getElementById('pp_salt_index').value,
            env: document.getElementById('pp_env').value,
            webhookSecret: document.getElementById('pp_webhook_secret').value
        },
        cashfree: {
            appId: document.getElementById('cf_app_id').value,
            secretKey: document.getElementById('cf_secret_key').value,
            env: document.getElementById('cf_env').value,
            webhookSecret: document.getElementById('cf_webhook_secret').value
        }
    };

    try {
        await fetch('/api/admin/config/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key: 'payment_settings', value: settings })
        });
        alert("Settings Synchronized Successfully");
        loadMonetization();
    } catch (err) { alert("Error saving config"); }
}
