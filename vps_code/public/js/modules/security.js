async function loadSecurity() {
    const modTitle = document.getElementById('modTitle');
    modTitle.innerText = "Security & Compliance";
    await SecurityModule.init();
}

const SecurityModule = {
    config: {
        isReviewMode: false,
        isOneMessageTrialEnabled: false,
        isScreenshotDisabled: true
    },

    async init() {
        document.getElementById('mainContent').innerHTML = `
            <div class="space-y-8">
                <div class="flex justify-between items-end">
                    <div class="space-y-2">
                        <div class="skeleton h-8 w-64"></div>
                        <div class="skeleton h-4 w-96"></div>
                    </div>
                    <div class="skeleton h-14 w-40 rounded-2xl"></div>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                    <div class="skeleton h-64 w-full rounded-[2.5rem]"></div>
                    <div class="skeleton h-64 w-full rounded-[2.5rem]"></div>
                    <div class="skeleton h-64 w-full rounded-[2.5rem]"></div>
                </div>
            </div>
        `;
        await this.fetchConfig();
        this.render();
    },

    async fetchConfig() {
        try {
            const data = await API.getConfig('review_mode_config');
            if (data.success && data.config) {
                this.config = { ...this.config, ...data.config };
            }
        } catch (error) {
            console.error('Error fetching security config:', error);
            showSystemToast('Error', 'Failed to load security configuration', 'bg-red-500');
        }
    },

    async syncConfig() {
        try {
            const updatedConfig = {
                isReviewMode: document.getElementById('isReviewMode').checked,
                isGradualEnabled: document.getElementById('isGradualEnabled')?.checked || false,
                isOneMessageTrialEnabled: document.getElementById('isOneMessageTrialEnabled').checked,
                isScreenshotDisabled: document.getElementById('isScreenshotDisabled').checked,
                monetizationStartDate: this.config.monetizationStartDate,
                updatedAt: new Date()
            };

            // Set start date if gradual is enabled now
            if (updatedConfig.isGradualEnabled && !updatedConfig.monetizationStartDate) {
                updatedConfig.monetizationStartDate = new Date();
            }

            const response = await API.updateConfig('review_mode_config', updatedConfig);

            if (response.success) {
                this.config = updatedConfig;
                showSystemToast('Success', 'Security policies updated successfully', 'bg-emerald-500');
            } else {
                showSystemToast('Error', 'Failed to update policies', 'bg-red-500');
            }
        } catch (error) {
            console.error('Error syncing security config:', error);
            showSystemToast('Error', 'Error updating security configuration', 'bg-red-500');
        }
    },

    render() {
        const content = `
            <div class="animate-fade space-y-8">
                <div class="flex justify-between items-end">
                    <div>
                        <h2 class="text-3xl font-black text-white tracking-tight">Security & Compliance</h2>
                        <p class="text-slate-500 font-medium">Manage app-wide security protocols and compliance modes.</p>
                    </div>
                    <button onclick="SecurityModule.syncConfig()" class="bg-emerald-500 hover:bg-emerald-600 text-black font-black px-8 py-4 rounded-2xl shadow-lg shadow-emerald-500/20 transition-all active:scale-95 flex items-center space-x-2">
                        <i class="fas fa-shield-check"></i>
                        <span>APPLY CHANGES</span>
                    </button>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
                    <!-- Screenshot Protection -->
                    <div class="glass p-10 rounded-[2.5rem] space-y-6 flex flex-col justify-between">
                        <div class="space-y-4">
                            <div class="w-14 h-14 bg-emerald-500/10 rounded-2xl flex items-center justify-center text-emerald-500">
                                <i class="fas fa-camera-slash text-2xl"></i>
                            </div>
                            <div>
                                <h3 class="text-xl font-bold text-white">Screenshot Protection</h3>
                                <p class="text-xs text-slate-500 mt-1 font-medium">Prevent users from taking screenshots or screen recordings.</p>
                            </div>
                        </div>
                        <div class="flex items-center justify-between p-4 bg-white/5 rounded-2xl border border-white/5">
                            <span class="text-[10px] font-black uppercase tracking-widest ${this.config.isScreenshotDisabled ? 'text-emerald-500' : 'text-slate-500'}">${this.config.isScreenshotDisabled ? 'Enabled' : 'Disabled'}</span>
                            <label class="relative inline-flex items-center cursor-pointer">
                                <input type="checkbox" id="isScreenshotDisabled" class="sr-only peer" ${this.config.isScreenshotDisabled ? 'checked' : ''} onchange="SecurityModule.toggleText(this, 'Enabled', 'Disabled')">
                                <div class="w-12 h-6 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-emerald-500"></div>
                            </label>
                        </div>
                    </div>

                    <!-- Review Mode / Standard Mode -->
                    <div class="glass p-10 rounded-[2.5rem] space-y-6 flex flex-col justify-between border-2 ${this.config.isReviewMode ? 'border-orange-500/50' : 'border-transparent'}">
                        <div class="space-y-4">
                            <div class="w-14 h-14 bg-orange-500/10 rounded-2xl flex items-center justify-center text-orange-500">
                                <i class="fas fa-store text-2xl"></i>
                            </div>
                            <div>
                                <h3 class="text-xl font-bold text-white">Global Review Mode</h3>
                                <p class="text-xs text-slate-500 mt-1 font-medium">Overrides everything. Hides all payments for ALL users (Use during App Review).</p>
                            </div>
                        </div>
                        <div class="flex items-center justify-between p-4 bg-white/5 rounded-2xl border border-white/5">
                            <span class="text-[10px] font-black uppercase tracking-widest ${this.config.isReviewMode ? 'text-orange-500' : 'text-slate-500'}">${this.config.isReviewMode ? 'Active' : 'Inactive'}</span>
                            <label class="relative inline-flex items-center cursor-pointer">
                                <input type="checkbox" id="isReviewMode" class="sr-only peer" ${this.config.isReviewMode ? 'checked' : ''} onchange="SecurityModule.toggleText(this, 'Active', 'Inactive')">
                                <div class="w-12 h-6 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-orange-500"></div>
                            </label>
                        </div>
                    </div>

                    <!-- Gradual Monetization -->
                    <div class="glass p-10 rounded-[2.5rem] space-y-6 flex flex-col justify-between border-2 ${this.config.isGradualEnabled ? 'border-blue-500/50' : 'border-transparent'}">
                        <div class="space-y-4">
                            <div class="w-14 h-14 bg-blue-500/10 rounded-2xl flex items-center justify-center text-blue-500">
                                <i class="fas fa-users-medical text-2xl"></i>
                            </div>
                            <div>
                                <h3 class="text-xl font-bold text-white">Gradual Monetization</h3>
                                <p class="text-xs text-slate-500 mt-1 font-medium">Keep Old Users FREE while requiring New Users to Pay.</p>
                            </div>
                        </div>
                        <div class="flex items-center justify-between p-4 bg-white/5 rounded-2xl border border-white/5">
                            <span class="text-[10px] font-black uppercase tracking-widest ${this.config.isGradualEnabled ? 'text-blue-500' : 'text-slate-500'}">${this.config.isGradualEnabled ? 'Hybrid Active' : 'Disabled'}</span>
                            <label class="relative inline-flex items-center cursor-pointer">
                                <input type="checkbox" id="isGradualEnabled" class="sr-only peer" ${this.config.isGradualEnabled ? 'checked' : ''} onchange="SecurityModule.toggleText(this, 'Hybrid Active', 'Disabled')">
                                <div class="w-12 h-6 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-500"></div>
                            </label>
                        </div>
                    </div>

                    <!-- One Message Trial -->
                    <div class="glass p-10 rounded-[2.5rem] space-y-6 flex flex-col justify-between">
                        <div class="space-y-4">
                            <div class="w-14 h-14 bg-blue-500/10 rounded-2xl flex items-center justify-center text-blue-500">
                                <i class="fas fa-comment-dots text-2xl"></i>
                            </div>
                            <div>
                                <h3 class="text-xl font-bold text-white">One-Message Trial</h3>
                                <p class="text-xs text-slate-500 mt-1 font-medium">Allows non-premium users to send one message per chat.</p>
                            </div>
                        </div>
                        <div class="flex items-center justify-between p-4 bg-white/5 rounded-2xl border border-white/5">
                            <span class="text-[10px] font-black uppercase tracking-widest ${this.config.isOneMessageTrialEnabled ? 'text-blue-500' : 'text-slate-500'}">${this.config.isOneMessageTrialEnabled ? 'Enabled' : 'Disabled'}</span>
                            <label class="relative inline-flex items-center cursor-pointer">
                                <input type="checkbox" id="isOneMessageTrialEnabled" class="sr-only peer" ${this.config.isOneMessageTrialEnabled ? 'checked' : ''} onchange="SecurityModule.toggleText(this, 'Enabled', 'Disabled')">
                                <div class="w-12 h-6 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-500"></div>
                            </label>
                        </div>
                    </div>
                </div>

                <div class="glass p-10 rounded-[2.5rem] bg-orange-500/5 border border-orange-500/10">
                    <div class="flex items-start space-x-6">
                        <div class="w-12 h-12 bg-orange-500/20 rounded-2xl flex items-center justify-center text-orange-500 shrink-0">
                            <i class="fas fa-circle-info text-xl"></i>
                        </div>
                        <div class="space-y-2">
                            <h4 class="text-lg font-bold text-white">Operational Warning</h4>
                            <p class="text-sm text-slate-400 leading-relaxed font-medium">
                                Screenshots Protection status is fetched by the app during splash screen. Users already inside the app may need to restart or wait for the next config sync (5-15 minutes) for changes to take effect. Standard Mode changes are applied instantly via Socket.io broadcast.
                            </p>
                        </div>
                    </div>
                </div>
            </div>
        `;
        document.getElementById('mainContent').innerHTML = content;
    },

    toggleText(input, onText, offText) {
        const span = input.parentElement.previousElementSibling;
        span.innerText = input.checked ? onText : offText;
        // Optionally update colors here too
    }
};
