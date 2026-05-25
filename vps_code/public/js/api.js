const API = {
    async getStats() {
        const res = await fetch('/api/admin/stats');
        return await res.json();
    },
    async getAdmins() {
        const res = await fetch('/api/admin/admins');
        return await res.json();
    },
    async getUsers(search = '') {
        const res = await fetch(`/api/admin/users${search ? '?search=' + encodeURIComponent(search) : ''}`);
        return await res.json();
    },
    async getUserFull(phone) {
        const res = await fetch(`/api/admin/user/${phone}/full`);
        return await res.json();
    },
    async updateUserStatus(phone, data) {
        const res = await fetch(`/api/admin/user/${phone}/update`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async clearChat(phone) {
        const res = await fetch(`/api/admin/user/${phone}/clear-chat`, { method: 'DELETE' });
        return await res.json();
    },
    async deleteAccount(phone) {
        const res = await fetch(`/api/admin/user/${phone}/delete-account`, { method: 'DELETE' });
        return await res.json();
    },
    async addAdminUserNote(phone, data) {
        const res = await fetch(`/api/admin/user/${phone}/note`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async sendDirectUserNotify(phone, data) {
        const res = await fetch(`/api/admin/user/${phone}/notify`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async getReports() {
        const res = await fetch('/api/admin/reports');
        return await res.json();
    },
    async getVerificationRequests() {
        const res = await fetch('/api/admin/verification/requests');
        return await res.json();
    },
    async approveVerification(phone) {
        const res = await fetch(`/api/admin/verification/approve/${phone}`, { method: 'POST' });
        return await res.json();
    },
    async getUserInboxes(phone) {
        const res = await fetch(`/api/admin/inbox/${phone}`);
        return await res.json();
    },
    async getChatHistory(p1, p2, page = 1) {
        const res = await fetch(`/api/admin/chat-history/${p1}/${p2}?page=${page}`);
        return await res.json();
    },
    async getPolicies() {
        const res = await fetch('/api/admin/policies');
        return await res.json();
    },
    async updatePolicy(type, url) {
        const res = await fetch('/api/admin/policy/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ type, url })
        });
        return await res.json();
    },
    async getSupportMessages(filters = {}) {
        const query = new URLSearchParams(filters).toString();
        const res = await fetch(`/api/admin/messages?${query}`);
        return await res.json();
    },
    async getTicketDetail(id) {
        const res = await fetch(`/api/admin/message/${id}`);
        return await res.json();
    },
    async updateTicket(id, data) {
        const res = await fetch(`/api/admin/message/${id}/reply`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async assignTicket(id, data) {
        const res = await fetch(`/api/admin/message/${id}/assign`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async addTicketNote(id, data) {
        const res = await fetch(`/api/admin/message/${id}/note`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async getAuditLogs() {
        const res = await fetch('/api/admin/audit-logs');
        const data = await res.json();
        return Array.isArray(data) ? data : (data.logs || []);
    },
    async getMonetizationStats() {
        const res = await fetch('/api/admin/monetization/stats');
        return await res.json();
    },
    async getPaymentHistory(page = 1) {
        const res = await fetch(`/api/admin/monetization/history?page=${page}`);
        return await res.json();
    },
    async broadcastNotification(title, message) {
        const res = await fetch('/api/admin/broadcast', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ title, message })
        });
        return await res.json();
    },
    async getConfig(key) {
        const res = await fetch(`/api/admin/config/${key}`);
        return await res.json();
    },
    async updateConfig(key, value) {
        const res = await fetch('/api/admin/config/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ key, value })
        });
        return await res.json();
    },
    // News Management
    async getAllNews() {
        const res = await fetch('/api/admin/news');
        return await res.json();
    },
    async addNews(data) {
        const res = await fetch('/api/admin/news', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async updateNews(id, data) {
        const res = await fetch(`/api/admin/news/${id}`, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        return await res.json();
    },
    async deleteNews(id) {
        const res = await fetch(`/api/admin/news/${id}`, { method: 'DELETE' });
        return await res.json();
    }
};
