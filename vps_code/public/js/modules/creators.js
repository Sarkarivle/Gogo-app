async function loadCreators() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Creator Manager";

    mainContent.innerHTML = `
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
