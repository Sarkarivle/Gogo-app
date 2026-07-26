async function loadNews() {
    console.log("📰 Loading News Management...");
    const modTitle = document.getElementById('modTitle');
    if (modTitle) modTitle.innerText = "News Management";

    try {
        await NewsModule.init();
    } catch (e) {
        console.error("❌ NewsModule Init Failed:", e);
        throw e; // Re-throw to be caught by app.js changeModule
    }
}

const NewsModule = {
    news: [],

    async init() {
        const mainContent = document.getElementById('mainContent');
        if (!mainContent) return;

        mainContent.innerHTML = `
            <div class="animate-fade space-y-8">
                <div class="flex justify-between items-end">
                    <div class="space-y-2">
                        <div class="skeleton h-8 w-64"></div>
                        <div class="skeleton h-4 w-96"></div>
                    </div>
                    <div class="skeleton h-14 w-40 rounded-2xl"></div>
                </div>
                <div class="space-y-6">
                    ${Array(5).fill('<div class="skeleton h-32 w-full rounded-3xl"></div>').join('')}
                </div>
            </div>
        `;

        await this.fetchNews();
        this.render();
    },

    async fetchNews() {
        try {
            console.log("📡 Fetching news articles...");
            const data = await API.getAllNews();
            if (data && data.success) {
                this.news = data.data || [];
                console.log(`✅ Loaded ${this.news.length} articles`);
            } else {
                this.news = [];
                console.warn("⚠️ API returned success:false for news");
            }
        } catch (error) {
            console.error('❌ Error fetching news:', error);
            this.news = [];
            if (typeof showSystemToast === 'function') {
                showSystemToast('Error', 'Failed to load news articles', 'bg-red-500');
            }
        }
    },

    async addNews() {
        const title = document.getElementById('news_title')?.value;
        const source = document.getElementById('news_source')?.value;
        const image_url = document.getElementById('news_image')?.value;
        const destination_url = document.getElementById('news_url')?.value;
        const category = document.getElementById('news_category')?.value;

        if (!title || !destination_url) {
            showSystemToast('Error', 'Title and URL are required', 'bg-red-500');
            return;
        }

        const formData = {
            title,
            source: source || "General",
            image_url: image_url || "",
            destination_url,
            category: category || "General",
            is_active: true,
            sort_order: 0
        };

        try {
            const data = await API.addNews(formData);
            if (data && data.success) {
                showSystemToast('Success', 'News article added', 'bg-emerald-500');
                if (typeof closeModal === 'function') closeModal();
                await this.init();
            }
        } catch (error) {
            console.error('Error adding news:', error);
            showSystemToast('Error', 'Failed to add news', 'bg-red-500');
        }
    },

    async deleteNews(id) {
        if (!confirm('Are you sure you want to delete this article?')) return;
        try {
            const data = await API.deleteNews(id);
            if (data && data.success) {
                showSystemToast('Success', 'News article deleted', 'bg-emerald-500');
                await this.init();
            }
        } catch (error) {
            console.error('Error deleting news:', error);
            showSystemToast('Error', 'Failed to delete news', 'bg-red-500');
        }
    },

    async toggleStatus(id, currentStatus) {
        try {
            const data = await API.updateNews(id, { is_active: !currentStatus });
            if (data && data.success) {
                showSystemToast('Success', 'Status updated', 'bg-emerald-500');
                await this.init();
            }
        } catch (error) {
            console.error('Error toggling status:', error);
            showSystemToast('Error', 'Failed to update status', 'bg-red-500');
        }
    },

    render() {
        const mainContent = document.getElementById('mainContent');
        if (!mainContent) return;

        const content = `
            <div class="animate-fade space-y-8">
                <div class="flex justify-between items-end">
                    <div>
                        <h2 class="text-3xl font-black text-white tracking-tight uppercase">News Management</h2>
                        <p class="text-slate-500 font-medium uppercase text-xs">Manage articles for the App Disguise Mode.</p>
                    </div>
                    <button onclick="NewsModule.showAddModal()" class="bg-blue-500 hover:bg-blue-600 text-white font-black px-8 py-4 rounded-2xl shadow-lg shadow-blue-500/20 transition-all active:scale-95 flex items-center space-x-2">
                        <i class="fas fa-plus"></i>
                        <span class="text-[10px] uppercase">Add New Article</span>
                    </button>
                </div>

                <div class="grid grid-cols-1 gap-6">
                    ${this.news.map(article => {
                        const date = article.published_at || article.createdAt || new Date();
                        const authenticatedImageUrl = API.getAuthUrl(article.image_url);
                        return `
                            <div class="glass p-6 rounded-3xl flex items-center space-x-6 border border-white/5 hover:border-white/10 transition">
                                <img src="${authenticatedImageUrl || 'https://via.placeholder.com/150'}" class="w-24 h-24 rounded-2xl object-cover bg-white/5" onerror="this.src='https://via.placeholder.com/150'">
                                <div class="flex-1 min-w-0">
                                    <div class="flex items-center space-x-2 mb-1">
                                        <span class="px-2 py-1 bg-blue-500/10 text-blue-500 text-[8px] font-black rounded uppercase">${article.category || 'General'}</span>
                                        <span class="text-[10px] text-slate-500 font-bold uppercase">${article.source || 'Unknown'} • ${new Date(date).toLocaleDateString()}</span>
                                    </div>
                                    <h3 class="text-lg font-black text-white truncate">${article.title || 'Untitled'}</h3>
                                    <p class="text-[10px] text-slate-500 truncate max-w-xl font-bold uppercase">${article.destination_url || '#'}</p>
                                </div>
                                <div class="flex items-center space-x-2">
                                    <button onclick="NewsModule.toggleStatus('${article._id}', ${article.is_active})" class="w-12 h-12 rounded-2xl ${article.is_active ? 'bg-emerald-500/10 text-emerald-500' : 'bg-slate-500/10 text-slate-500'} flex items-center justify-center transition-all hover:scale-105" title="${article.is_active ? 'Active' : 'Inactive'}">
                                        <i class="fas ${article.is_active ? 'fa-eye' : 'fa-eye-slash'}"></i>
                                    </button>
                                    <button onclick="NewsModule.deleteNews('${article._id}')" class="w-12 h-12 rounded-2xl bg-red-500/10 text-red-500 flex items-center justify-center hover:bg-red-500 hover:text-white transition-all hover:scale-105">
                                        <i class="fas fa-trash"></i>
                                    </button>
                                </div>
                            </div>
                        `;
                    }).join('')}
                    ${this.news.length === 0 ? '<div class="glass p-20 rounded-[3rem] text-center opacity-30 uppercase font-black"><i class="fas fa-newspaper text-4xl mb-4 block"></i> No news articles found. Add your first article to start.</div>' : ''}
                </div>
            </div>
        `;
        mainContent.innerHTML = content;
    },

    showAddModal() {
        const content = `
            <div class="space-y-6">
                <div class="grid grid-cols-2 gap-6">
                    <div class="space-y-2">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Article Title</label>
                        <input type="text" id="news_title" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-bold text-sm">
                    </div>
                    <div class="space-y-2">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Source Name</label>
                        <input type="text" id="news_source" placeholder="e.g. Times of India" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-bold text-sm">
                    </div>
                </div>
                <div class="space-y-2">
                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Image URL</label>
                    <input type="text" id="news_image" placeholder="https://..." class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-medium text-sm">
                </div>
                <div class="space-y-2">
                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Destination URL</label>
                    <input type="text" id="news_url" placeholder="https://..." class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-medium text-sm">
                </div>
                <div class="space-y-2">
                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Category</label>
                    <select id="news_category" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-bold text-sm uppercase">
                        <option value="General">General</option>
                        <option value="Technology">Technology</option>
                        <option value="Politics">Politics</option>
                        <option value="Sports">Sports</option>
                        <option value="Entertainment">Entertainment</option>
                    </select>
                </div>
                <button onclick="NewsModule.addNews()" class="w-full bg-blue-500 hover:bg-blue-600 text-white font-black py-5 rounded-2xl shadow-lg shadow-blue-500/20 transition-all active:scale-[0.98] uppercase text-[10px]">
                    Save Article
                </button>
            </div>
        `;
        if (typeof UI !== 'undefined' && UI.modal) {
            UI.modal.show('Add News Article', content);
        }
    }
};
