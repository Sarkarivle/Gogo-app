async function loadTrialOffer() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Trial Offer Management";

    // Skeleton Offer View
    mainContent.innerHTML = `
        <div class="space-y-10 animate-fade max-w-4xl mx-auto pb-20">
            <div class="grid grid-cols-2 gap-6">
                ${UI.skeletonCard()}
                ${UI.skeletonCard()}
            </div>
            <div class="skeleton h-[40rem] rounded-[3rem]"></div>
        </div>
    `;

    try {
        const data = await API.getConfig('trial_offer_settings');

        let settings = data.config || {
            amount: 1,
            currency: '₹',
            offerTitle: '₹1 Offer',
            offerDescription: 'Activate Gold Status at just ₹1 for the first month.',
            timerMinutes: 10,
            showSkipButton: true,
            skipButtonText: 'Not now, go to home',
            urgentNote: '₹1 ऑफर सिर्फ 10 मिनट के लिए मान्य'
        };

        mainContent.innerHTML = `
            <div class="space-y-10 animate-fade max-w-4xl mx-auto pb-20">
                <div class="grid grid-cols-2 gap-6">
                    ${UI.card('Trial Price', settings.currency + settings.amount, 'Current Active Price', 'text-amber-500')}
                    ${UI.card('Timer', settings.timerMinutes + ' Min', 'Urgency Duration', 'text-red-500')}
                </div>

                <div class="glass p-10 rounded-[3rem] space-y-8 border border-amber-500/10">
                    <div class="flex items-center justify-between border-b border-white/5 pb-6">
                        <div>
                            <h3 class="text-xl font-black text-white uppercase">Offer Configuration</h3>
                            <p class="text-[10px] text-slate-500 mt-1 uppercase font-bold">Control how the trial page looks to users</p>
                        </div>
                    </div>

                    <div class="grid grid-cols-2 gap-6">
                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Trial Amount (Number only)</label>
                            <input type="number" id="trial_amount" value="${settings.amount}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                        </div>
                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Currency Symbol</label>
                            <input type="text" id="trial_currency" value="${settings.currency}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                        </div>
                    </div>

                    <div class="space-y-2">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Offer Title (Main Heading)</label>
                        <input type="text" id="trial_title" value="${settings.offerTitle}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                    </div>

                    <div class="space-y-2">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Offer Description</label>
                        <textarea id="trial_desc" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white h-24">${settings.offerDescription}</textarea>
                    </div>

                    <div class="grid grid-cols-2 gap-6">
                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Timer (Minutes)</label>
                            <input type="number" id="trial_timer" value="${settings.timerMinutes}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                        </div>
                        <div class="space-y-2">
                            <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Urgent Note (Hindi/Urgency Text)</label>
                            <input type="text" id="trial_urgent" value="${settings.urgentNote}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                        </div>
                    </div>
                </div>

                <div class="glass p-10 rounded-[3rem] space-y-8 border border-white/5">
                    <div class="flex items-center justify-between border-b border-white/5 pb-6">
                        <div>
                            <h3 class="text-xl font-black text-white uppercase">Navigation Control</h3>
                            <p class="text-[10px] text-slate-500 mt-1 uppercase font-bold">Control the "Skip" or "Home" behavior</p>
                        </div>
                    </div>

                    <div class="flex items-center space-x-4 p-4 glass rounded-2xl">
                        <input type="checkbox" id="trial_show_skip" ${settings.showSkipButton ? 'checked' : ''} class="w-5 h-5 accent-orange-500">
                        <label class="text-xs font-bold text-white uppercase">Enable "Skip / Go to Home" Button</label>
                    </div>

                    <div class="space-y-2">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest block ml-2">Button Text</label>
                        <input type="text" id="trial_skip_text" value="${settings.skipButtonText}" class="w-full bg-white/5 border border-white/5 p-4 rounded-2xl outline-none text-xs text-white">
                    </div>
                </div>

                <div class="pt-4">
                    <button onclick="saveTrialSettings()" class="w-full py-5 bg-orange-500 text-black rounded-2xl text-[11px] font-black uppercase hover:scale-[1.02] transition shadow-lg shadow-orange-500/20">
                        Update Global Trial Offer
                    </button>
                </div>
            </div>
        `;
    } catch (err) {
        console.error(err);
        mainContent.innerHTML = `<p class="p-20 text-center text-red-500 font-black uppercase">Error Loading Trial Settings</p>`;
    }
}

async function saveTrialSettings() {
    const settings = {
        amount: parseInt(document.getElementById('trial_amount').value),
        currency: document.getElementById('trial_currency').value,
        offerTitle: document.getElementById('trial_title').value,
        offerDescription: document.getElementById('trial_desc').value,
        timerMinutes: parseInt(document.getElementById('trial_timer').value),
        urgentNote: document.getElementById('trial_urgent').value,
        showSkipButton: document.getElementById('trial_show_skip').checked,
        skipButtonText: document.getElementById('trial_skip_text').value
    };

    try {
        const data = await API.updateConfig('trial_offer_settings', settings);
        if (data.success) {
            alert("Trial Settings Updated Successfully");
            loadTrialOffer();
        } else {
            alert("Failed to update settings");
        }
    } catch (err) {
        alert("Network error while saving");
    }
}
