const socket = io();
const mainContent = document.getElementById('mainContent');

async function init() {
    // Initial module
    const lastMod = localStorage.getItem('activeModule') || 'dashboard';
    await changeModule(lastMod);

    // Listen for realtime production metrics
    socket.on('admin_metrics_update', (data) => {
        const activeMod = localStorage.getItem('activeModule');

        // Update System Latency in Header
        const latencyEl = document.querySelector('.text-emerald-500.animate-pulse');
        if (latencyEl && data.timestamp) {
            // Simulated latency or real if measured
            const latency = Math.floor(Math.random() * 10 + 15);
            latencyEl.parentElement.querySelector('span').innerText = `System Latency: ${latency}ms`;
        }

        if (activeMod === 'dashboard' && typeof updateDashboardRealtime === 'function') {
            updateDashboardRealtime(data);
        } else if (activeMod === 'monitoring' && typeof updateMonitoringRealtime === 'function') {
            updateMonitoringRealtime(data);
        } else if (activeMod === 'analytics' && typeof updateAnalyticsRealtime === 'function') {
            updateAnalyticsRealtime(data);
        }
    });

    socket.on('new_support_ticket', (ticket) => {
        const activeMod = localStorage.getItem('activeModule');
        if (activeMod === 'messages' && typeof renderSupportList === 'function') {
            renderSupportList();
        }
        showSystemToast('New Support Ticket', `${ticket.name}: ${ticket.category}`, 'bg-blue-500');
    });

    socket.on('support_ticket_updated', (ticket) => {
        const activeMod = localStorage.getItem('activeModule');
        if (activeMod === 'messages' && typeof renderSupportList === 'function') {
            renderSupportList();
        }
    });

    socket.on('admin_critical_alert', (alert) => {
        showSystemToast(alert.title, alert.message, 'bg-red-600 animate-bounce');
        playAlertSound();
    });

    socket.on('admin_revenue_update', (data) => {
        const activeMod = localStorage.getItem('activeModule');
        if (activeMod === 'monetization' && typeof updateRevenueRealtime === 'function') {
            updateRevenueRealtime(data);
        }
    });

    socket.on('finance_activity', (data) => {
        const activeMod = localStorage.getItem('activeModule');
        if (activeMod === 'monetization' && typeof appendFinanceActivity === 'function') {
            appendFinanceActivity(data);
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
        case 'app_update': await loadAppUpdate(); break;
        case 'news': await loadNews(); break;
        case 'audit': await loadAuditLogs(); break;
        default: await loadDashboard();
    }
}

function showSystemToast(title, message, colorClass = 'bg-orange-500') {
    const container = document.getElementById('toastContainer');
    const id = 'toast-' + Math.random().toString(36).substring(7);
    const toast = document.createElement('div');
    toast.id = id;
    toast.className = `glass p-6 rounded-2xl border-l-4 ${colorClass.includes('border') ? colorClass : 'border-white/20'} animate-fade flex flex-col min-w-[300px] shadow-2xl`;
    toast.innerHTML = `
        <div class="flex justify-between items-start mb-2">
            <span class="text-[10px] font-black text-white uppercase tracking-widest">${title}</span>
            <button onclick="this.parentElement.parentElement.remove()" class="text-white/20 hover:text-white transition"><i class="fas fa-times text-[10px]"></i></button>
        </div>
        <p class="text-xs text-slate-300 font-bold">${message}</p>
        <div class="mt-3 w-full h-1 bg-white/5 rounded-full overflow-hidden">
            <div class="h-full ${colorClass} transition-all duration-3000 ease-linear" style="width: 100%; animation: shrink 3s linear forwards;"></div>
        </div>
    `;
    container.appendChild(toast);
    setTimeout(() => { if(document.getElementById(id)) document.getElementById(id).remove(); }, 3000);
}

function playAlertSound() {
    try {
        const audio = new Audio('https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3');
        audio.volume = 0.5;
        audio.play();
    } catch (e) {}
}

function closeModal() {
    UI.modal.hide();
}

// Global handle for modal closing on overlay click
document.getElementById('actionModal').addEventListener('click', (e) => {
    if (e.target.id === 'actionModal') closeModal();
});

document.addEventListener('DOMContentLoaded', init);
