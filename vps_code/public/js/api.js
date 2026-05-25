const API = {
    getToken() {
        return localStorage.getItem('admin_token');
    },
    setToken(token) {
        localStorage.setItem('admin_token', token);
    },
    clearToken() {
        localStorage.removeItem('admin_token');
        window.location.reload();
    },
    async request(url, options = {}) {
        const token = this.getToken();
        const headers = {
            'Content-Type': 'application/json',
            ...options.headers
        };
        if (token) {
            headers['Authorization'] = `Bearer ${token}`;
        }

        const res = await fetch(url, { ...options, headers });

        if (res.status === 401) {
            this.clearToken();
            throw new Error("Session expired. Please login again.");
        }

        return await res.json();
    },

    async login(username, password) {
        const data = await this.request('/api/admin/login', {
            method: 'POST',
            body: JSON.stringify({ username, password })
        });
        if (data.success) {
            this.setToken(data.token);
            localStorage.setItem('admin_user', JSON.stringify(data.admin));
        }
        return data;
    },

    async getStats() {
        return await this.request('/api/admin/stats');
    },
    async getAdmins() {
        return await this.request('/api/admin/admins');
    },
    async getUsers(search = '') {
        return await this.request(`/api/admin/users${search ? '?search=' + encodeURIComponent(search) : ''}`);
    },
    async getUserFull(phone) {
        return await this.request(`/api/admin/user/${phone}/full`);
    },
    async updateUserStatus(phone, data) {
        return await this.request(`/api/admin/user/${phone}/update`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async clearChat(phone) {
        return await this.request(`/api/admin/user/${phone}/clear-chat`, { method: 'DELETE' });
    },
    async deleteAccount(phone) {
        return await this.request(`/api/admin/user/${phone}/delete-account`, { method: 'DELETE' });
    },
    async addAdminUserNote(phone, data) {
        return await this.request(`/api/admin/user/${phone}/note`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async sendDirectUserNotify(phone, data) {
        return await this.request(`/api/admin/user/${phone}/notify`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async getReports() {
        return await this.request('/api/admin/reports');
    },
    async getVerificationRequests() {
        return await this.request('/api/admin/verification/requests');
    },
    async approveVerification(phone) {
        return await this.request(`/api/admin/verification/approve/${phone}`, { method: 'POST' });
    },
    async getUserInboxes(phone) {
        return await this.request(`/api/admin/inbox/${phone}`);
    },
    async getChatHistory(p1, p2, page = 1) {
        return await this.request(`/api/admin/chat-history/${p1}/${p2}?page=${page}`);
    },
    async getPolicies() {
        return await this.request('/api/admin/policies');
    },
    async updatePolicy(type, url) {
        return await this.request('/api/admin/policy/update', {
            method: 'POST',
            body: JSON.stringify({ type, url })
        });
    },
    async getSupportMessages(filters = {}) {
        const query = new URLSearchParams(filters).toString();
        return await this.request(`/api/admin/messages?${query}`);
    },
    async getTicketDetail(id) {
        return await this.request(`/api/admin/message/${id}`);
    },
    async updateTicket(id, data) {
        return await this.request(`/api/admin/message/${id}/reply`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async assignTicket(id, data) {
        return await this.request(`/api/admin/message/${id}/assign`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async addTicketNote(id, data) {
        return await this.request(`/api/admin/message/${id}/note`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async getAuditLogs() {
        const data = await this.request('/api/admin/audit-logs');
        return Array.isArray(data) ? data : (data.logs || []);
    },
    async getMonetizationStats() {
        return await this.request('/api/admin/monetization/stats');
    },
    async getPaymentHistory(page = 1) {
        return await this.request(`/api/admin/monetization/history?page=${page}`);
    },
    async broadcastNotification(title, message) {
        return await this.request('/api/admin/broadcast', {
            method: 'POST',
            body: JSON.stringify({ title, message })
        });
    },
    async getConfig(key) {
        return await this.request(`/api/admin/config/${key}`);
    },
    async updateConfig(key, value) {
        return await this.request('/api/admin/config/update', {
            method: 'POST',
            body: JSON.stringify({ key, value })
        });
    },
    async getAllNews() {
        return await this.request('/api/admin/news');
    },
    async addNews(data) {
        return await this.request('/api/admin/news', {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async updateNews(id, data) {
        return await this.request(`/api/admin/news/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data)
        });
    },
    async deleteNews(id) {
        return await this.request(`/api/admin/news/${id}`, { method: 'DELETE' });
    }
};
