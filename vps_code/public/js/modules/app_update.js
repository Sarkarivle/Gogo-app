async function loadAppUpdate() {
    const modTitle = document.getElementById('modTitle');
    modTitle.innerText = "App Update Management";
    await AppUpdateModule.init();
}

const AppUpdateModule = {
    config: {
        latest_version: '1.0.0',
        force_update_enabled: false,
        update_title: 'New Update Available',
        update_message: 'We have improved performance, security, and calling experience.',
        playstore_url: '',
        minimum_supported_version: '1.0.0'
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
                <div class="grid grid-cols-3 gap-8">
                    <div class="col-span-2 space-y-8">
                        <div class="skeleton h-80 w-full rounded-[2.5rem]"></div>
                        <div class="skeleton h-64 w-full rounded-[2.5rem]"></div>
                    </div>
                    <div class="space-y-8">
                        <div class="skeleton h-96 w-full rounded-[2.5rem]"></div>
                        <div class="skeleton h-64 w-full rounded-[2.5rem]"></div>
                    </div>
                </div>
            </div>
        `;
        await this.fetchConfig();
        this.render();
    },

    async fetchConfig() {
        try {
            const data = await API.getConfig('app_update_config');
            if (data.success && data.config && Object.keys(data.config).length > 0) {
                this.config = { ...this.config, ...data.config };
            }
        } catch (error) {
            console.error('Error fetching app update config:', error);
            showSystemToast('Error', 'Failed to load app update configuration', 'bg-red-500');
        }
    },

    async syncConfig() {
        try {
            const updatedConfig = {
                latest_version: document.getElementById('latest_version').value,
                force_update_enabled: document.getElementById('force_update_enabled').checked,
                update_title: document.getElementById('update_title').value,
                update_message: document.getElementById('update_message').value,
                playstore_url: document.getElementById('playstore_url').value,
                minimum_supported_version: document.getElementById('minimum_supported_version').value,
                updated_at: new Date()
            };

            const response = await API.updateConfig('app_update_config', updatedConfig);

            if (response.success) {
                this.config = updatedConfig;
                showSystemToast('Success', 'Configuration synchronized successfully', 'bg-emerald-500');
            } else {
                showSystemToast('Error', 'Failed to sync configuration', 'bg-red-500');
            }
        } catch (error) {
            console.error('Error syncing config:', error);
            showSystemToast('Error', 'Error syncing configuration', 'bg-red-500');
        }
    },

    render() {
        const content = `
            <div class="animate-fade space-y-8">
                <div class="flex justify-between items-end">
                    <div>
                        <h2 class="text-3xl font-black text-white tracking-tight">App Update Management</h2>
                        <p class="text-slate-500 font-medium">Control the latest version and force update policies for all users.</p>
                    </div>
                    <button onclick="AppUpdateModule.syncConfig()" class="bg-orange-500 hover:bg-orange-600 text-black font-black px-8 py-4 rounded-2xl shadow-lg shadow-orange-500/20 transition-all active:scale-95 flex items-center space-x-2">
                        <i class="fas fa-sync-alt"></i>
                        <span>SYNC CONFIG</span>
                    </button>
                </div>

                <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
                    <!-- Version Control -->
                    <div class="lg:col-span-2 space-y-8">
                        <div class="glass p-10 rounded-[2.5rem] space-y-8">
                            <div class="flex items-center space-x-4 mb-2">
                                <div class="w-12 h-12 bg-blue-500/10 rounded-2xl flex items-center justify-center text-blue-500">
                                    <i class="fas fa-code-branch text-xl"></i>
                                </div>
                                <h3 class="text-xl font-bold text-white">Version Configuration</h3>
                            </div>

                            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                                <div class="space-y-2">
                                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Latest Version (Production)</label>
                                    <input type="text" id="latest_version" value="${this.config.latest_version}" placeholder="e.g. 1.0.7" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-orange-500 transition-all font-bold">
                                </div>
                                <div class="space-y-2">
                                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Minimum Supported Version</label>
                                    <input type="text" id="minimum_supported_version" value="${this.config.minimum_supported_version}" placeholder="e.g. 1.0.0" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-orange-500 transition-all font-bold">
                                </div>
                            </div>

                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Play Store / App Update Link</label>
                                <div class="relative">
                                    <i class="fab fa-google-play absolute left-6 top-1/2 -translate-y-1/2 text-slate-500"></i>
                                    <input type="text" id="playstore_url" value="${this.config.playstore_url}" placeholder="https://play.google.com/store/apps/details?id=..." class="w-full bg-white/5 border border-white/10 rounded-2xl pl-14 pr-6 py-4 text-white focus:outline-none focus:border-orange-500 transition-all font-medium">
                                </div>
                            </div>
                        </div>

                        <div class="glass p-10 rounded-[2.5rem] space-y-8">
                            <div class="flex items-center space-x-4 mb-2">
                                <div class="w-12 h-12 bg-orange-500/10 rounded-2xl flex items-center justify-center text-orange-500">
                                    <i class="fas fa-comment-alt text-xl"></i>
                                </div>
                                <h3 class="text-xl font-bold text-white">Update Prompt Content</h3>
                            </div>

                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Update Dialog Title</label>
                                <input type="text" id="update_title" value="${this.config.update_title}" placeholder="New Update Available" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-orange-500 transition-all font-bold">
                            </div>

                            <div class="space-y-2">
                                <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Update Message / What's New</label>
                                <textarea id="update_message" rows="4" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-orange-500 transition-all font-medium resize-none">${this.config.update_message}</textarea>
                            </div>
                        </div>
                    </div>

                    <!-- Force Update Toggle -->
                    <div class="space-y-8">
                        <div class="glass p-10 rounded-[2.5rem] space-y-8">
                            <div class="flex items-center justify-between">
                                <div class="flex items-center space-x-4">
                                    <div class="w-12 h-12 bg-red-500/10 rounded-2xl flex items-center justify-center text-red-500">
                                        <i class="fas fa-shield-alt text-xl"></i>
                                    </div>
                                    <h3 class="text-xl font-bold text-white">Policy</h3>
                                </div>
                                <label class="relative inline-flex items-center cursor-pointer">
                                    <input type="checkbox" id="force_update_enabled" onchange="AppUpdateModule.updateStatusText(this.checked)" class="sr-only peer" ${this.config.force_update_enabled ? 'checked' : ''}>
                                    <div class="w-14 h-8 bg-white/10 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[4px] after:left-[4px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-6 after:w-6 after:transition-all peer-checked:bg-orange-500"></div>
                                </label>
                            </div>

                            <div class="p-6 rounded-2xl bg-red-500/10 border border-red-500/20">
                                <p class="text-xs font-bold text-red-400 uppercase mb-2">Warning</p>
                                <p class="text-sm text-red-200/70 leading-relaxed font-medium">
                                    Enabling <b>Force Update</b> will block all users with a version lower than the <b>Latest Version</b>. They will be required to update before continuing.
                                </p>
                            </div>

                            <div class="pt-4 space-y-4">
                                <div class="flex items-center justify-between text-xs font-bold uppercase tracking-widest text-slate-500">
                                    <span>Status</span>
                                    <span id="policy_status_text" class="${this.config.force_update_enabled ? 'text-red-500' : 'text-emerald-500'}">${this.config.force_update_enabled ? 'Strict Blocking' : 'Optional Update'}</span>
                                </div>
                                <div class="w-full h-1 bg-white/5 rounded-full overflow-hidden">
                                    <div id="policy_status_bar" class="h-full ${this.config.force_update_enabled ? 'bg-red-500' : 'bg-emerald-500'}" style="width: 100%"></div>
                                </div>
                            </div>
                        </div>

                        <!-- Live Preview Mockup -->
                        <div class="glass p-8 rounded-[2.5rem] space-y-6">
                            <h3 class="text-xs font-black text-slate-500 uppercase tracking-widest">Update Modal Preview</h3>
                            <div class="bg-black/40 rounded-3xl p-6 border border-white/5 space-y-4">
                                <div class="w-12 h-12 bg-orange-500 rounded-2xl flex items-center justify-center mx-auto shadow-lg shadow-orange-500/20">
                                    <i class="fas fa-rocket text-black"></i>
                                </div>
                                <h4 class="text-center font-bold text-white" id="preview_title">${this.config.update_title}</h4>
                                <p class="text-center text-[10px] text-slate-400 px-4" id="preview_message">${this.config.update_message}</p>
                                <div class="bg-orange-500 text-black text-[10px] font-black py-3 rounded-xl text-center uppercase tracking-widest">Update Now</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
        document.getElementById('mainContent').innerHTML = content;

        // Add listeners for live preview
        document.getElementById('update_title').addEventListener('input', (e) => {
            document.getElementById('preview_title').innerText = e.target.value;
        });
        document.getElementById('update_message').addEventListener('input', (e) => {
            document.getElementById('preview_message').innerText = e.target.value;
        });
    },

    updateStatusText(enabled) {
        const textEl = document.getElementById('policy_status_text');
        const barEl = document.getElementById('policy_status_bar');
        if (enabled) {
            textEl.innerText = 'Strict Blocking';
            textEl.className = 'text-red-500';
            barEl.className = 'h-full bg-red-500';
        } else {
            textEl.innerText = 'Optional Update';
            textEl.className = 'text-emerald-500';
            barEl.className = 'h-full bg-emerald-500';
        }
    }
};
