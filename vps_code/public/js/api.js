const API = {
    async getStats() {
        const res = await fetch('/api/admin/stats');
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
    async getSupportMessages() {
        const res = await fetch('/api/admin/messages');
        return await res.json();
    },
    async broadcastNotification(message) {
        const res = await fetch('/api/admin/broadcast', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message })
        });
        return await res.json();
    }
};
