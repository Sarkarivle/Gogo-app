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
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
            ...options.headers
        };
        if (token) {
            headers['Authorization'] = `Bearer ${token}`;
        }

        console.log(`📡 API Request: ${url}`);
        const res = await fetch(url, {
            ...options,
            headers,
            cache: 'no-store'
        });

        if (!res.ok) {
            const errData = await res.json().catch(() => ({}));
            console.error(`❌ API Error [${res.status}] for ${url}:`, errData);
            if (res.status === 401) {
                console.warn("🔐 Session expired or invalid token. Redirecting to login...");
                this.clearToken();
                throw new Error("Session expired. Please login again.");
            }
            throw new Error(errData.message || `Server error (${res.status})`);
        }

        const data = await res.json();
        console.log(`✅ API Response [${res.status}] for ${url}:`, data.success ? 'Success' : 'Failed');
        return data;
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
    async updateAdmin(id, data) {
        return await this.request(`/api/admin/admin/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data)
        });
    },
    async deleteAdmin(id) {
        return await this.request(`/api/admin/admin/${id}`, { method: 'DELETE' });
    },
    async getUsers(filters = {}) {
        const query = new URLSearchParams(filters).toString();
        return await this.request(`/api/admin/users${query ? '?' + query : ''}`);
    },
    async getUserFull(phone) {
        return await this.request(`/api/admin/user/${phone}/full`);
    },
    async getUserTimeline(phone) {
        return await this.request(`/api/admin/user/${phone}/timeline`);
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
    async bulkDeleteUsers(phones) {
        return await this.request('/api/admin/users/bulk-delete', {
            method: 'POST',
            body: JSON.stringify({ phones })
        });
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
    async updateReportStatus(id, status) {
        return await this.request('/api/admin/reports/handle', {
            method: 'POST',
            body: JSON.stringify({ reportId: id, id: id, status })
        });
    },
    async getVerificationRequests() {
        return await this.request('/api/admin/verification/requests');
    },
    async approveVerification(phone) {
        return await this.request(`/api/admin/verification/approve/${phone}`, { method: 'POST' });
    },
    async rejectVerification(phone, data) {
        return await this.request(`/api/admin/verification/reject/${phone}`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
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
    async getMonitoringData() {
        return await this.request('/api/admin/monitoring/sockets');
    },
    async getAuditLogs() {
        return await this.request('/api/admin/audit-logs');
    },
    async getAnalyticsDetailed() {
        return await this.request('/api/admin/analytics/detailed');
    },
    async getAllMedia(filter = '', reportedOnly = false) {
        return await this.request(`/api/admin/media/all?filter=${filter}&reportedOnly=${reportedOnly}`);
    },
    async deleteMedia(data) {
        return await this.request('/api/admin/media/delete', {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async getFeatureFlags() {
        return await this.request('/api/admin/feature-flags');
    },
    async toggleFeatureFlag(key, isEnabled) {
        return await this.request('/api/admin/feature-flags/toggle', {
            method: 'POST',
            body: JSON.stringify({ key, isEnabled })
        });
    },
    async deleteNews(id) {
        return await this.request(`/api/admin/news/${id}`, { method: 'DELETE' });
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
    async getConfig(key) {
        return await this.request(`/api/admin/config/${key}`);
    },
    async updateConfig(key, value) {
        return await this.request('/api/admin/config/update', {
            method: 'POST',
            body: JSON.stringify({ key, value })
        });
    },
    async getMonetizationStats() {
        return await this.request('/api/admin/monetization/stats');
    },
    async getPaymentHistory(page = 1) {
        return await this.request(`/api/admin/monetization/history?page=${page}`);
    },
    async getGPFullDashboard(page = 1) {
        const url = page.toString().includes('sync=true') ? `/api/admin/monetization/google-play-dashboard?page=1&sync=true` : `/api/admin/monetization/google-play-dashboard?page=${page}`;
        return await this.request(url);
    },
    async broadcastNotification(title, message, targets = [], scheduledAt = null) {
        return await this.request('/api/admin/broadcast', {
            method: 'POST',
            body: JSON.stringify({ title, message, targets, scheduledAt })
        });
    },
    async getCampaigns() {
        return await this.request('/api/admin/campaigns');
    },
    async syncProvider(phone) {
        return await this.request('/api/payment/sync-provider', {
            method: 'POST',
            body: JSON.stringify({ phone })
        });
    },
    // Generic methods
    async get(endpoint) {
        return await this.request(`/api${endpoint}`);
    },
    async post(endpoint, data) {
        return await this.request(`/api${endpoint}`, {
            method: 'POST',
            body: JSON.stringify(data)
        });
    },
    async uploadFile(endpoint, formData) {
        const token = this.getToken();
        const headers = {
            'Authorization': `Bearer ${token}`
        };
        console.log(`📡 API Upload Request: ${endpoint}`);
        const res = await fetch(`/api${endpoint}`, {
            method: 'POST',
            headers,
            body: formData
        });
        if (!res.ok) throw new Error(`Upload failed (${res.status})`);
        return await res.json();
    },
    getAuthUrl(url) {
        if (!url) return '';
        if (!url.startsWith('/api/media')) return url;
        const token = this.getToken();
        return url.includes('?') ? `${url}&auth=${token}` : `${url}?auth=${token}`;
    }
};
