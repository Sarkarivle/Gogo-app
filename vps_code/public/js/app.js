let socket;

async function init() {
    console.log("🚀 GoGo System Initializing...");
    const token = API.getToken();
    const loginOverlay = document.getElementById('loginOverlay');
    const sidebar = document.getElementById('adminSidebar');
    const mainWrapper = document.getElementById('adminMainWrapper');

    if (!token || token === 'null' || token === 'undefined') {
        if (loginOverlay) loginOverlay.style.display = 'flex';
        setupLoginForm();
        return;
    }

    // Show UI immediately
    if (sidebar) sidebar.classList.remove('hidden'), sidebar.classList.add('flex');
    if (mainWrapper) mainWrapper.classList.remove('hidden'), mainWrapper.classList.add('flex');
    if (loginOverlay) loginOverlay.style.display = 'none';

    // Socket Connection
    socket = io({ auth: { token: token }, transports: ['websocket'] });
    setupSocketListeners();

    // Load Initial Module
    const savedMod = localStorage.getItem('activeModule');
    const startMod = (savedMod && savedMod !== 'null') ? savedMod : 'dashboard';

    console.log(`📡 Starting module: ${startMod}`);
    setTimeout(() => changeModule(startMod), 100);
}

async function changeModule(mod) {
    if (!mod) mod = 'dashboard';

    const modTitle = document.getElementById('modTitle');
    const mainContent = document.getElementById('mainContent');

    if (!modTitle || !mainContent) {
        setTimeout(() => changeModule(mod), 100);
        return;
    }

    console.log(`🔄 Navigation Request: ${mod}`);

    // Update Sidebar UI
    document.querySelectorAll('.sidebar-item').forEach(el => el.classList.remove('active'));
    const navItem = document.getElementById('nav-' + mod);
    if (navItem) navItem.classList.add('active');

    localStorage.setItem('activeModule', mod);

    try {
        switch(mod) {
            case 'dashboard': await loadDashboard(); break;
            case 'users': await loadUsers(); break;
            case 'reports': await loadReports(); break;
            case 'verifications': await loadVerifications(); break;
            case 'monitoring': await loadMonitoring(); break;
            case 'analytics': await loadAnalytics(); break;
            case 'monetization': await loadMonetization(); break;
            case 'discovery':
                if (typeof loadDiscovery === 'function') await loadDiscovery();
                else throw new Error("Discovery module script not loaded properly");
                break;
            case 'media': await loadMedia(); break;
            case 'notifications': await loadNotifications(); break;
            case 'policies': await loadPolicies(); break;
            case 'messages': await loadSupportMessages(); break;
            case 'app_update': await loadAppUpdate(); break;
            case 'news': await loadNews(); break;
            case 'marketing': await loadMarketing(); break;
            case 'audit': await loadAuditLogs(); break;
            case 'database': await loadDatabaseTools(); break;
            case 'admins': await loadAdmins(); break;
            default:
                console.warn(`Fallback to dashboard for: ${mod}`);
                await loadDashboard();
        }
    } catch (err) {
        console.error(`❌ Module Error [${mod}]:`, err);
        mainContent.innerHTML = `
            <div class="p-20 text-center">
                <h2 class="text-red-500 font-black uppercase">System Error</h2>
                <p class="text-xs text-slate-500 mt-2">${err.message}</p>
                <button onclick="location.reload()" class="mt-6 px-8 py-3 glass rounded-xl text-[10px] font-black uppercase">Reload Admin</button>
            </div>
        `;
    }
}

function setupLoginForm() {
    const form = document.getElementById('loginForm');
    if (!form) return;
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        try {
            const res = await API.login(document.getElementById('username').value, document.getElementById('password').value);
            if (res.success) window.location.reload();
        } catch (e) { alert("Login failed"); }
    });
}

function setupSocketListeners() {
    if (!socket) return;
    socket.on('admin_metrics_update', (data) => {
        if (localStorage.getItem('activeModule') === 'dashboard') updateDashboardRealtime?.(data);
    });
}

function logout() { API.clearToken(); }
function closeModal() { UI.modal.hide(); }

window.addEventListener('load', init);
document.addEventListener('click', (e) => { if (e.target.id === 'actionModal') closeModal(); });
