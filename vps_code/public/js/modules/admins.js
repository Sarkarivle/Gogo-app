async function loadAdmins() {
    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');
    modTitle.innerText = "Admin Staff Management";

    // Skeleton Grid Loading
    mainContent.innerHTML = `
        <div class="space-y-8 animate-fade">
            <div class="flex justify-between items-center">
                <div class="skeleton h-10 w-64"></div>
                <div class="skeleton h-12 w-32 rounded-xl"></div>
            </div>
            <div class="grid grid-cols-3 gap-6">
                ${Array(6).fill('<div class="skeleton h-24 w-full rounded-[2rem]"></div>').join('')}
            </div>
        </div>
    `;

    try {
        const admins = await API.getAdmins();

        mainContent.innerHTML = `
            <div class="space-y-8 animate-fade">
                <div class="flex justify-between items-center">
                    <div>
                        <h2 class="text-2xl font-black text-white">Access Control</h2>
                        <p class="text-slate-500 text-xs font-bold uppercase tracking-widest mt-1">Manage system administrators and moderators</p>
                    </div>
                    <button onclick="showCreateAdminModal()" class="bg-orange-500 text-black px-6 py-3 rounded-xl font-black text-xs uppercase hover:scale-105 transition-all shadow-lg shadow-orange-500/20">
                        <i class="fas fa-plus mr-2"></i> New Admin
                    </button>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    ${admins.map(a => `
                        <div class="glass p-6 rounded-[2rem] flex items-center justify-between border border-white/5 hover:border-orange-500/30 transition-all group">
                            <div class="flex items-center space-x-4">
                                <div class="w-14 h-14 rounded-2xl bg-white/5 flex items-center justify-center text-xl font-black text-orange-500">
                                    ${a.username[0].toUpperCase()}
                                </div>
                                <div>
                                    <h3 class="text-white font-bold">${a.username}</h3>
                                    <p class="text-[10px] font-black uppercase ${a.role === 'Super Admin' ? 'text-purple-400' : 'text-slate-500'} tracking-widest">${a.role}</p>
                                </div>
                            </div>
                            <div class="flex flex-col space-y-2 opacity-0 group-hover:opacity-100 transition-opacity">
                                <button onclick='showEditAdminModal(${JSON.stringify(a).replace(/'/g, "&apos;")})' class="w-8 h-8 rounded-lg bg-blue-500/10 text-blue-500 flex items-center justify-center hover:bg-blue-500 hover:text-white transition">
                                    <i class="fas fa-edit text-[10px]"></i>
                                </button>
                                <button onclick="deleteAdminAccount('${a._id}')" class="w-8 h-8 rounded-lg bg-red-500/10 text-red-500 flex items-center justify-center hover:bg-red-500 hover:text-white transition">
                                    <i class="fas fa-trash text-[10px]"></i>
                                </button>
                            </div>
                        </div>
                    `).join('')}
                </div>
            </div>
        `;
    } catch (err) {
        mainContent.innerHTML = `<div class="p-20 text-center text-red-500 font-bold">Failed to load admin list</div>`;
    }
}

function showCreateAdminModal() {
    UI.modal.show(
        `<div class="flex items-center space-x-4">
            <div class="w-10 h-10 bg-purple-500/20 rounded-xl flex items-center justify-center text-purple-500"><i class="fas fa-user-shield"></i></div>
            <div>
                <h2 class="text-xl font-black text-white">Create New Admin</h2>
                <p class="text-[10px] text-slate-500 uppercase font-bold tracking-widest">Internal Staff Access</p>
            </div>
        </div>`,
        `<div class="space-y-6">
            <div class="grid grid-cols-2 gap-6">
                <div>
                    <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Username</label>
                    <input type="text" id="new_admin_user" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition">
                </div>
                <div>
                    <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Password</label>
                    <input type="password" id="new_admin_pass" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition">
                </div>
            </div>
            <div>
                <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Access Role</label>
                <select id="new_admin_role" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition">
                    <option value="Moderator">Moderator</option>
                    <option value="Support">Support Staff</option>
                    <option value="Super Admin">Super Admin</option>
                </select>
            </div>
            <div class="pt-6">
                <button onclick="submitNewAdmin()" class="w-full bg-white text-black font-black py-4 rounded-2xl hover:bg-orange-500 hover:text-white transition-all uppercase text-xs tracking-widest">Create Administrator Account</button>
            </div>
        </div>`
    );
}

async function submitNewAdmin() {
    const username = document.getElementById('new_admin_user').value;
    const password = document.getElementById('new_admin_pass').value;
    const role = document.getElementById('new_admin_role').value;

    if(!username || !password) return alert("All fields required");

    try {
        const data = await API.request('/api/admin/create-initial-admin', {
            method: 'POST',
            body: JSON.stringify({ username, password, role, secret: 'GOGO_INIT_SECRET_99' })
        });
        if(data.success) {
            UI.modal.hide();
            loadAdmins();
            showSystemToast("Success", "New admin created successfully", "bg-emerald-500");
        } else {
            alert(data.message || "Failed to create admin");
        }
    } catch(e) {
        alert("Error creating admin");
    }
}

function showEditAdminModal(admin) {
    UI.modal.show(
        `<div class="flex items-center space-x-4">
            <div class="w-10 h-10 bg-blue-500/20 rounded-xl flex items-center justify-center text-blue-500"><i class="fas fa-user-edit"></i></div>
            <div>
                <h2 class="text-xl font-black text-white">Edit Staff Member</h2>
                <p class="text-[10px] text-slate-500 uppercase font-bold tracking-widest">Update credentials for ${admin.username}</p>
            </div>
        </div>`,
        `<div class="space-y-6">
            <div class="grid grid-cols-2 gap-6">
                <div>
                    <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Username</label>
                    <input type="text" id="edit_admin_user" value="${admin.username}" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition">
                </div>
                <div>
                    <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">New Password</label>
                    <input type="password" id="edit_admin_pass" placeholder="••••••••" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition">
                    <p class="text-[8px] text-slate-600 mt-1 uppercase font-bold">Leave blank to keep current password</p>
                </div>
            </div>
            <div>
                <label class="text-[10px] font-bold text-slate-500 uppercase tracking-widest ml-1">Access Role</label>
                <select id="edit_admin_role" class="w-full bg-white/5 border border-white/10 rounded-2xl p-4 mt-2 text-white focus:outline-none focus:border-orange-500 transition">
                    <option value="Moderator" ${admin.role === 'Moderator' ? 'selected' : ''}>Moderator</option>
                    <option value="Support" ${admin.role === 'Support Staff' || admin.role === 'Support' ? 'selected' : ''}>Support Staff</option>
                    <option value="Super Admin" ${admin.role === 'Super Admin' ? 'selected' : ''}>Super Admin</option>
                </select>
            </div>
            <div class="pt-6">
                <button onclick="submitEditAdmin('${admin._id}')" class="w-full bg-orange-500 text-black font-black py-4 rounded-2xl hover:scale-[1.02] transition-all uppercase text-xs tracking-widest">Apply Identity Changes</button>
            </div>
        </div>`
    );
}

async function submitEditAdmin(id) {
    const username = document.getElementById('edit_admin_user').value;
    const password = document.getElementById('edit_admin_pass').value;
    const role = document.getElementById('edit_admin_role').value;

    if(!username) return alert("Username is required");

    const data = { username, role };
    if(password) data.password = password;

    try {
        const res = await API.updateAdmin(id, data);
        if(res.success) {
            UI.modal.hide();
            loadAdmins();
            showSystemToast("Updated", "Staff credentials synchronized", "bg-blue-500");
        } else {
            alert(res.message || "Failed to update admin");
        }
    } catch(e) {
        alert("Error updating admin");
    }
}

async function deleteAdminAccount(id) {
    if(!confirm("Are you sure you want to PERMANENTLY remove this administrator's access?")) return;

    try {
        const res = await API.deleteAdmin(id);
        if(res.success) {
            loadAdmins();
            showSystemToast("Removed", "Admin access revoked", "bg-red-500");
        } else {
            alert(res.message || "Action failed");
        }
    } catch(e) {
        alert("Server error during deletion");
    }
}
