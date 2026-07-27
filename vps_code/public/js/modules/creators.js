let creatorActiveTab = 'list';

async function loadCreators() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Creator Manager";

    mainContent.innerHTML = `
        <div class="space-y-6">
            <div class="flex space-x-2 glass p-1.5 rounded-2xl w-fit">
                <button onclick="switchCreatorTab('list')" id="creatorTab-list" class="creator-tab px-6 py-2.5 rounded-xl text-xs font-black uppercase tracking-widest transition">
                    <i class="fas fa-user-astronaut mr-2"></i> Creator List
                </button>
                <button onclick="switchCreatorTab('settings')" id="creatorTab-settings" class="creator-tab px-6 py-2.5 rounded-xl text-xs font-black uppercase tracking-widest transition">
                    <i class="fas fa-sliders mr-2"></i> Creator Settings
                </button>
                <button onclick="switchCreatorTab('randomvideos')" id="creatorTab-randomvideos" class="creator-tab px-6 py-2.5 rounded-xl text-xs font-black uppercase tracking-widest transition">
                    <i class="fas fa-clapperboard mr-2"></i> Random Videos
                </button>
            </div>
            <div id="creatorTabContent"></div>
        </div>
    `;

    renderCreatorTabStyles();
    await switchCreatorTab(creatorActiveTab);
}

function renderCreatorTabStyles() {
    document.querySelectorAll('.creator-tab').forEach((el) => {
        const isActive = el.id === `creatorTab-${creatorActiveTab}`;
        el.className = `creator-tab px-6 py-2.5 rounded-xl text-xs font-black uppercase tracking-widest transition ${isActive ? 'bg-gradient-to-r from-orange-500 to-orange-600 text-white shadow-lg shadow-orange-500/20' : 'text-slate-500 hover:text-white'}`;
    });
}

async function switchCreatorTab(tab) {
    creatorActiveTab = tab;
    renderCreatorTabStyles();
    if (tab === 'settings') {
        await renderCreatorSettingsTab();
    } else if (tab === 'randomvideos') {
        await renderRandomVideosTab();
    } else {
        await renderCreatorListTab();
    }
}

// ============ TAB 1: Creator List (existing feed-profile management) ============
async function renderCreatorListTab() {
    const content = document.getElementById('creatorTabContent');
    content.innerHTML = `
        <div class="space-y-6">
            <div class="flex justify-between items-center">
                <p class="text-xs text-slate-500 font-bold uppercase tracking-widest">Profiles shown in the app's Discover feed</p>
                <button onclick="openAddCreatorModal()" class="bg-gradient-to-r from-orange-500 to-orange-600 text-white font-black px-6 py-3 rounded-2xl shadow-lg shadow-orange-500/20 hover:scale-[1.02] active:scale-[0.98] transition-all text-xs uppercase">
                    <i class="fas fa-plus mr-2"></i> Add Creator
                </button>
            </div>
            <div id="creatorGrid" class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
                <div class="glass p-4 rounded-[1.5rem] animate-pulse h-72"></div>
                <div class="glass p-4 rounded-[1.5rem] animate-pulse h-72"></div>
                <div class="glass p-4 rounded-[1.5rem] animate-pulse h-72"></div>
                <div class="glass p-4 rounded-[1.5rem] animate-pulse h-72"></div>
            </div>
        </div>
    `;
    await refreshCreatorGrid();
}

async function refreshCreatorGrid() {
    const grid = document.getElementById('creatorGrid');
    if (!grid) return;
    try {
        const res = await API.get('/admin/creators');
        const creators = res.creators || [];
        if (creators.length === 0) {
            grid.innerHTML = `
                <div class="col-span-full text-center py-24">
                    <i class="fas fa-user-astronaut text-slate-700 text-5xl mb-4"></i>
                    <p class="text-slate-500 text-sm font-bold">No creators added yet</p>
                </div>`;
        } else {
            grid.innerHTML = creators.map(creatorCardHtml).join('');
        }
    } catch (e) {
        grid.innerHTML = `<div class="col-span-full text-center py-24 text-red-500 text-xs font-bold">Failed to load creators: ${e.message}</div>`;
    }
}

function creatorCardHtml(c) {
    const photo = (c.profileImages && c.profileImages[0]) ? API.getAuthUrl(c.profileImages[0]) : '';
    const statusColor = c.isOnline ? 'bg-emerald-500' : 'bg-slate-600';
    const statusText = c.isOnline ? 'Online' : 'Offline';
    return `
    <div class="glass rounded-[2rem] overflow-hidden group relative animate-fade">
        <div class="h-56 bg-black/40 relative overflow-hidden">
            ${photo ? `<img src="${photo}" class="w-full h-full object-cover">` : `<div class="w-full h-full flex items-center justify-center"><i class="fas fa-user text-slate-700 text-4xl"></i></div>`}
            <div class="absolute top-3 right-3 ${statusColor} text-white text-[9px] font-black uppercase px-3 py-1 rounded-full flex items-center space-x-1">
                <span class="w-1.5 h-1.5 bg-white rounded-full"></span><span>${statusText}</span>
            </div>
        </div>
        <div class="p-5">
            <p class="text-white font-black text-sm">${c.name}, ${c.age}</p>
            <p class="text-slate-500 text-xs mt-1 line-clamp-2">${c.bio || 'No bio'}</p>
            <button onclick="deleteCreator('${c._id}')" class="mt-4 w-full text-red-500 hover:bg-red-500 hover:text-white transition text-[10px] font-black uppercase py-2 rounded-xl border border-red-500/30">
                <i class="fas fa-trash mr-1"></i> Remove
            </button>
        </div>
    </div>`;
}

function openAddCreatorModal() {
    UI.modal.show('Add Creator', `
        <form id="creatorForm" class="space-y-5 max-w-lg">
            <div>
                <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Photo</label>
                <input type="file" id="creatorPhotoInput" accept="image/*" required class="w-full bg-white/5 border border-white/10 rounded-2xl p-3 mt-2 text-white text-xs file:mr-4 file:py-2 file:px-4 file:rounded-xl file:border-0 file:bg-orange-500 file:text-black file:font-bold file:text-xs">
                <img id="creatorPhotoPreview" class="hidden mt-3 w-24 h-24 object-cover rounded-2xl border border-white/10">
            </div>
            <div>
                <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Name</label>
                <input type="text" id="creatorNameInput" required class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition" placeholder="Creator name">
            </div>
            <div>
                <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Age</label>
                <input type="number" id="creatorAgeInput" required min="18" max="99" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition" placeholder="25">
            </div>
            <div>
                <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">About</label>
                <textarea id="creatorAboutInput" rows="3" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition" placeholder="Short bio / tagline"></textarea>
            </div>
            <div>
                <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Status</label>
                <select id="creatorStatusInput" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition">
                    <option value="true">Online</option>
                    <option value="false">Offline</option>
                </select>
            </div>
            <button type="submit" id="creatorAddBtn" class="w-full bg-gradient-to-r from-orange-500 to-orange-600 text-white font-black py-4 rounded-2xl shadow-lg shadow-orange-500/20 hover:scale-[1.02] active:scale-[0.98] transition-all text-xs uppercase">
                Add Creator
            </button>
            <p id="creatorFormError" class="text-red-500 text-xs font-bold text-center hidden"></p>
        </form>
    `);

    document.getElementById('creatorPhotoInput').addEventListener('change', (e) => {
        const file = e.target.files[0];
        const preview = document.getElementById('creatorPhotoPreview');
        if (file) {
            preview.src = URL.createObjectURL(file);
            preview.classList.remove('hidden');
        }
    });

    document.getElementById('creatorForm').addEventListener('submit', submitCreatorForm);
}

async function submitCreatorForm(e) {
    e.preventDefault();
    const btn = document.getElementById('creatorAddBtn');
    const errEl = document.getElementById('creatorFormError');
    errEl.classList.add('hidden');

    const photoFile = document.getElementById('creatorPhotoInput').files[0];
    if (!photoFile) {
        errEl.textContent = 'Please select a photo';
        errEl.classList.remove('hidden');
        return;
    }

    const fd = new FormData();
    fd.append('photo', photoFile);
    fd.append('name', document.getElementById('creatorNameInput').value);
    fd.append('age', document.getElementById('creatorAgeInput').value);
    fd.append('about', document.getElementById('creatorAboutInput').value);
    fd.append('isOnline', document.getElementById('creatorStatusInput').value);

    btn.disabled = true;
    btn.innerText = 'Adding...';

    try {
        const res = await API.uploadFile('/admin/creators', fd);
        if (res.success) {
            showSystemToast("Creator Added", `${res.creator.name} is now live in the feed`, 'bg-emerald-500');
            closeModal();
            await refreshCreatorGrid();
        } else {
            throw new Error(res.message || 'Failed to add creator');
        }
    } catch (err) {
        errEl.textContent = err.message;
        errEl.classList.remove('hidden');
    } finally {
        btn.disabled = false;
        btn.innerText = 'Add Creator';
    }
}

async function deleteCreator(id) {
    if (!confirm('Remove this creator from the feed?')) return;
    try {
        await API.request(`/api/admin/creators/${id}`, { method: 'DELETE' });
        showSystemToast("Creator Removed", "Profile removed from feed", 'bg-orange-500');
        await refreshCreatorGrid();
    } catch (e) {
        showSystemToast("Error", e.message, 'bg-red-500');
    }
}

// ============ TAB 2: Creator Settings (simulated-call greeting audio) ============
async function renderCreatorSettingsTab() {
    const content = document.getElementById('creatorTabContent');
    content.innerHTML = `
        <div class="space-y-8 max-w-3xl">
            <div class="glass rounded-[2rem] p-8">
                <p class="text-xs text-slate-500 font-bold uppercase tracking-widest mb-1">Simulated Call — Greeting Voice</p>
                <h2 class="text-white text-lg font-black mb-2">"Hello" clips played on the fake-call preview</h2>
                <p class="text-slate-500 text-xs leading-relaxed mb-6">
                    When a free-mode user (or a user out of call credits) taps Call, the app rings and then plays one of
                    these clips at random before cutting to the paywall / buy-credits screen. Upload short voice clips
                    here — they go live in the app immediately, no update needed.
                </p>

                <label class="block border-2 border-dashed border-white/10 rounded-2xl p-8 text-center cursor-pointer hover:border-orange-500/50 transition" id="greetingDropZone">
                    <i class="fas fa-cloud-arrow-up text-3xl text-slate-600 mb-3"></i>
                    <p class="text-slate-400 text-xs font-bold">Click to choose an audio file</p>
                    <p class="text-slate-600 text-[10px] mt-1">MP3, M4A, WAV, AAC or OGG — max 10MB</p>
                    <input type="file" id="greetingAudioInput" accept=".mp3,.m4a,.wav,.aac,.ogg,audio/*" class="hidden">
                </label>
                <p id="greetingUploadStatus" class="text-xs font-bold text-center mt-4 hidden"></p>
            </div>

            <div>
                <p class="text-xs text-slate-500 font-bold uppercase tracking-widest mb-4">Live Clips</p>
                <div id="greetingClipsList" class="space-y-3">
                    <div class="glass p-4 rounded-2xl animate-pulse h-16"></div>
                    <div class="glass p-4 rounded-2xl animate-pulse h-16"></div>
                </div>
            </div>
        </div>
    `;

    document.getElementById('greetingAudioInput').addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (file) uploadGreetingAudio(file);
    });

    await refreshGreetingClipsList();
}

async function refreshGreetingClipsList() {
    const list = document.getElementById('greetingClipsList');
    if (!list) return;
    try {
        const res = await API.get('/admin/creators/greeting-audio');
        const clips = res.clips || [];
        if (clips.length === 0) {
            list.innerHTML = `
                <div class="glass rounded-2xl p-8 text-center">
                    <i class="fas fa-microphone-slash text-slate-700 text-2xl mb-2"></i>
                    <p class="text-slate-500 text-xs font-bold">No greeting clips uploaded yet — the fake call currently ends silently.</p>
                </div>`;
        } else {
            list.innerHTML = clips.map(greetingClipHtml).join('');
        }
    } catch (e) {
        list.innerHTML = `<div class="text-center py-8 text-red-500 text-xs font-bold">Failed to load clips: ${e.message}</div>`;
    }
}

function greetingClipHtml(clip) {
    const uploadedAt = clip.uploadedAt ? new Date(clip.uploadedAt).toLocaleString() : '';
    return `
    <div class="glass rounded-2xl p-4 flex items-center gap-4 animate-fade">
        <div class="w-10 h-10 rounded-xl bg-orange-500/10 flex items-center justify-center shrink-0">
            <i class="fas fa-waveform-lines text-orange-500"></i>
        </div>
        <div class="flex-1 min-w-0">
            <p class="text-white text-xs font-bold truncate">${clip.filename}</p>
            <p class="text-slate-600 text-[10px]">${clip.sizeKb} KB &middot; ${uploadedAt}</p>
        </div>
        <audio controls preload="none" src="${clip.url}" class="h-9" style="max-width: 220px;"></audio>
        <button onclick="deleteGreetingAudio('${clip.filename}')" class="w-9 h-9 rounded-xl flex items-center justify-center text-red-500 hover:bg-red-500 hover:text-white transition border border-red-500/30 shrink-0">
            <i class="fas fa-trash text-xs"></i>
        </button>
    </div>`;
}

async function uploadGreetingAudio(file) {
    const statusEl = document.getElementById('greetingUploadStatus');
    statusEl.className = 'text-xs font-bold text-center mt-4 text-slate-400';
    statusEl.textContent = `Uploading ${file.name}...`;
    statusEl.classList.remove('hidden');

    const fd = new FormData();
    fd.append('audio', file);

    try {
        const res = await API.uploadFile('/admin/creators/greeting-audio', fd);
        if (!res.success) throw new Error(res.message || 'Upload failed');
        statusEl.className = 'text-xs font-bold text-center mt-4 text-emerald-500';
        statusEl.textContent = 'Uploaded — now live in the app';
        showSystemToast("Greeting Uploaded", `${file.name} is now live`, 'bg-emerald-500');
        await refreshGreetingClipsList();
    } catch (e) {
        statusEl.className = 'text-xs font-bold text-center mt-4 text-red-500';
        statusEl.textContent = e.message;
        showSystemToast("Upload Failed", e.message, 'bg-red-500');
    } finally {
        document.getElementById('greetingAudioInput').value = '';
    }
}

async function deleteGreetingAudio(filename) {
    if (!confirm(`Remove "${filename}" from the greeting rotation?`)) return;
    try {
        await API.request(`/api/admin/creators/greeting-audio/${encodeURIComponent(filename)}`, { method: 'DELETE' });
        showSystemToast("Clip Removed", filename, 'bg-orange-500');
        await refreshGreetingClipsList();
    } catch (e) {
        showSystemToast("Error", e.message, 'bg-red-500');
    }
}

// ============ TAB 3: Random Videos (fake-partner videos for Random Live) ============
async function renderRandomVideosTab() {
    const content = document.getElementById('creatorTabContent');
    content.innerHTML = `
        <div class="space-y-8 max-w-3xl">
            <div class="glass rounded-[2rem] p-8">
                <p class="text-xs text-slate-500 font-bold uppercase tracking-widest mb-1">Random Live — Fake Partner Videos</p>
                <h2 class="text-white text-lg font-black mb-2">Videos played as a "partner" during random matching</h2>
                <p class="text-slate-500 text-xs leading-relaxed mb-6">
                    For free-mode users, every few real random-match connections the app plays one of these clips
                    full-screen instead of matching with a real stranger — designed to look like a normal live video
                    chat. The clip auto-ends after a few seconds and the user is nudged toward premium. Upload short
                    clips (ideally with someone talking) here — they go live in the app immediately, no update needed.
                </p>

                <label class="block border-2 border-dashed border-white/10 rounded-2xl p-8 text-center cursor-pointer hover:border-orange-500/50 transition" id="randomVideoDropZone">
                    <i class="fas fa-film text-3xl text-slate-600 mb-3"></i>
                    <p class="text-slate-400 text-xs font-bold">Click to choose a video file</p>
                    <p class="text-slate-600 text-[10px] mt-1">MP4, MOV or WEBM — max 80MB</p>
                    <input type="file" id="randomVideoInput" accept=".mp4,.mov,.webm,video/*" class="hidden">
                </label>
                <p id="randomVideoUploadStatus" class="text-xs font-bold text-center mt-4 hidden"></p>
            </div>

            <div>
                <p class="text-xs text-slate-500 font-bold uppercase tracking-widest mb-4">Live Clips</p>
                <div id="randomVideoClipsList" class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div class="glass p-4 rounded-2xl animate-pulse h-40"></div>
                    <div class="glass p-4 rounded-2xl animate-pulse h-40"></div>
                </div>
            </div>
        </div>
    `;

    document.getElementById('randomVideoInput').addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (file) uploadRandomVideo(file);
    });

    await refreshRandomVideoClipsList();
}

async function refreshRandomVideoClipsList() {
    const list = document.getElementById('randomVideoClipsList');
    if (!list) return;
    try {
        const res = await API.get('/admin/creators/random-live-videos');
        const clips = res.clips || [];
        if (clips.length === 0) {
            list.innerHTML = `
                <div class="col-span-full glass rounded-2xl p-8 text-center">
                    <i class="fas fa-video-slash text-slate-700 text-2xl mb-2"></i>
                    <p class="text-slate-500 text-xs font-bold">No videos uploaded yet — Random Live only matches with real users right now.</p>
                </div>`;
        } else {
            list.innerHTML = clips.map(randomVideoClipHtml).join('');
        }
    } catch (e) {
        list.innerHTML = `<div class="col-span-full text-center py-8 text-red-500 text-xs font-bold">Failed to load clips: ${e.message}</div>`;
    }
}

function randomVideoClipHtml(clip) {
    const uploadedAt = clip.uploadedAt ? new Date(clip.uploadedAt).toLocaleString() : '';
    return `
    <div class="glass rounded-2xl p-3 animate-fade">
        <video controls preload="metadata" src="${clip.url}" class="w-full h-40 object-cover rounded-xl bg-black"></video>
        <div class="flex items-center justify-between mt-3">
            <div class="min-w-0">
                <p class="text-white text-xs font-bold truncate">${clip.filename}</p>
                <p class="text-slate-600 text-[10px]">${clip.sizeKb} KB &middot; ${uploadedAt}</p>
            </div>
            <button onclick="deleteRandomVideo('${clip.filename}')" class="w-9 h-9 rounded-xl flex items-center justify-center text-red-500 hover:bg-red-500 hover:text-white transition border border-red-500/30 shrink-0">
                <i class="fas fa-trash text-xs"></i>
            </button>
        </div>
    </div>`;
}

async function uploadRandomVideo(file) {
    const statusEl = document.getElementById('randomVideoUploadStatus');
    statusEl.className = 'text-xs font-bold text-center mt-4 text-slate-400';
    statusEl.textContent = `Uploading ${file.name}...`;
    statusEl.classList.remove('hidden');

    const fd = new FormData();
    fd.append('video', file);

    try {
        const res = await API.uploadFile('/admin/creators/random-live-videos', fd);
        if (!res.success) throw new Error(res.message || 'Upload failed');
        statusEl.className = 'text-xs font-bold text-center mt-4 text-emerald-500';
        statusEl.textContent = 'Uploaded — now live in the app';
        showSystemToast("Video Uploaded", `${file.name} is now live`, 'bg-emerald-500');
        await refreshRandomVideoClipsList();
    } catch (e) {
        statusEl.className = 'text-xs font-bold text-center mt-4 text-red-500';
        statusEl.textContent = e.message;
        showSystemToast("Upload Failed", e.message, 'bg-red-500');
    } finally {
        document.getElementById('randomVideoInput').value = '';
    }
}

async function deleteRandomVideo(filename) {
    if (!confirm(`Remove "${filename}" from the Random Live rotation?`)) return;
    try {
        await API.request(`/api/admin/creators/random-live-videos/${encodeURIComponent(filename)}`, { method: 'DELETE' });
        showSystemToast("Video Removed", filename, 'bg-orange-500');
        await refreshRandomVideoClipsList();
    } catch (e) {
        showSystemToast("Error", e.message, 'bg-red-500');
    }
}
