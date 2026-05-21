const socket = io();
const mainContent = document.getElementById('mainContent');

async function init() {
    // Initial module
    const lastMod = localStorage.getItem('activeModule') || 'dashboard';
    await changeModule(lastMod);

    // Listen for realtime updates if needed
    socket.on('stats_update', (data) => {
        if (localStorage.getItem('activeModule') === 'dashboard') {
            // Optional: refresh dashboard or specific cards
        }
    });
}

async function changeModule(mod) {
    // UI Update
    document.querySelectorAll('.sidebar-item').forEach(el => el.classList.remove('active'));
    const navItem = document.getElementById('nav-' + mod);
    if (navItem) navItem.classList.add('active');

    localStorage.setItem('activeModule', mod);

    // Route Logic
    switch(mod) {
        case 'dashboard': await loadDashboard(); break;
        case 'users': await loadUsers(); break;
        case 'reports': await loadReports(); break;
        case 'verifications': await loadVerifications(); break;
        case 'policies': await loadPolicies(); break;
        case 'messages': await loadSupportMessages(); break;
        case 'monitoring': await loadMonitoring(); break;
        case 'analytics': await loadAnalytics(); break;
        case 'notifications': await loadNotifications(); break;
        case 'monetization': await loadMonetization(); break;
        case 'moderation': await loadModeration(); break;
        case 'discovery': await loadDiscovery(); break;
        case 'media': await loadMedia(); break;
        case 'server': await loadServerHealth(); break;
        case 'database': await loadDatabaseTools(); break;
        case 'fraud': await loadFraudMonitoring(); break;
        case 'audit': await loadAuditLogs(); break;
        case 'flags': await loadFeatureFlags(); break;
        default: await loadDashboard();
    }
}

function closeModal() {
    UI.modal.hide();
}

// Global handle for modal closing on overlay click
document.getElementById('actionModal').addEventListener('click', (e) => {
    if (e.target.id === 'actionModal') closeModal();
});

document.addEventListener('DOMContentLoaded', init);
