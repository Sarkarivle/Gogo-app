async function loadNews() {
    const modTitle = document.getElementById('modTitle');
    modTitle.innerText = "News Management";
    await NewsModule.init();
}

const NewsModule = {
    news: [],

    async init() {
        document.getElementById('mainContent').innerHTML = UI.loader();
        await this.fetchNews();
        this.render();
    },

    async fetchNews() {
        try {
            const data = await API.getAllNews();
            if (data.success) {
                this.news = data.data;
            }
        } catch (error) {
            console.error('Error fetching news:', error);
            showSystemToast('Error', 'Failed to load news articles', 'bg-red-500');
        }
    },

    async addNews() {
        const formData = {
            title: document.getElementById('news_title').value,
            source: document.getElementById('news_source').value,
            image_url: document.getElementById('news_image').value,
            destination_url: document.getElementById('news_url').value,
            category: document.getElementById('news_category').value,
            is_active: true,
            sort_order: 0
        };

        try {
            const data = await API.addNews(formData);
            if (data.success) {
                showSystemToast('Success', 'News article added', 'bg-emerald-500');
                closeModal();
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
            if (data.success) {
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
            if (data.success) {
                showSystemToast('Success', 'Status updated', 'bg-emerald-500');
                await this.init();
            }
        } catch (error) {
            console.error('Error toggling status:', error);
            showSystemToast('Error', 'Failed to update status', 'bg-red-500');
        }
    },

    render() {
        const content = `
            <div class="animate-fade space-y-8">
                <div class="flex justify-between items-end">
                    <div>
                        <h2 class="text-3xl font-black text-white tracking-tight">News Management</h2>
                        <p class="text-slate-500 font-medium">Manage articles for the App Disguise Mode.</p>
                    </div>
                    <button onclick="NewsModule.showAddModal()" class="bg-blue-500 hover:bg-blue-600 text-white font-black px-8 py-4 rounded-2xl shadow-lg shadow-blue-500/20 transition-all active:scale-95 flex items-center space-x-2">
                        <i class="fas fa-plus"></i>
                        <span>ADD NEW ARTICLE</span>
                    </button>
                </div>

                <div class="grid grid-cols-1 gap-6">
                    ${this.news.map(article => `
                        <div class="glass p-6 rounded-3xl flex items-center space-x-6">
                            <img src="${article.image_url || 'https://via.placeholder.com/150'}" class="w-24 h-24 rounded-2xl object-cover bg-white/5">
                            <div class="flex-1">
                                <div class="flex items-center space-x-2 mb-1">
                                    <span class="px-2 py-1 bg-blue-500/10 text-blue-500 text-[10px] font-bold rounded-lg uppercase">${article.category}</span>
                                    <span class="text-xs text-slate-500 font-medium">${article.source} • ${new Date(article.published_at).toLocaleDateString()}</span>
                                </div>
                                <h3 class="text-lg font-bold text-white">${article.title}</h3>
                                <p class="text-sm text-slate-500 truncate max-w-xl">${article.destination_url}</p>
                            </div>
                            <div class="flex items-center space-x-2">
                                <button onclick="NewsModule.toggleStatus('${article._id}', ${article.is_active})" class="w-10 h-10 rounded-xl ${article.is_active ? 'bg-emerald-500/10 text-emerald-500' : 'bg-slate-500/10 text-slate-500'} flex items-center justify-center transition-all">
                                    <i class="fas ${article.is_active ? 'fa-eye' : 'fa-eye-slash'}"></i>
                                </button>
                                <button onclick="NewsModule.deleteNews('${article._id}')" class="w-10 h-10 rounded-xl bg-red-500/10 text-red-500 flex items-center justify-center hover:bg-red-500 hover:text-white transition-all">
                                    <i class="fas fa-trash"></i>
                                </button>
                            </div>
                        </div>
                    `).join('')}
                    ${this.news.length === 0 ? '<div class="glass p-20 rounded-[3rem] text-center"><p class="text-slate-500 font-bold">No news articles found. Add your first article to start.</p></div>' : ''}
                </div>
            </div>
        `;
        document.getElementById('mainContent').innerHTML = content;
    },

    showAddModal() {
        const content = `
            <div class="space-y-6">
                <div class="grid grid-cols-2 gap-6">
                    <div class="space-y-2">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Article Title</label>
                        <input type="text" id="news_title" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-bold">
                    </div>
                    <div class="space-y-2">
                        <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Source Name</label>
                        <input type="text" id="news_source" placeholder="e.g. Times of India" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-bold">
                    </div>
                </div>
                <div class="space-y-2">
                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Image URL</label>
                    <input type="text" id="news_image" placeholder="https://..." class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-medium">
                </div>
                <div class="space-y-2">
                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Destination URL</label>
                    <input type="text" id="news_url" placeholder="https://..." class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-medium">
                </div>
                <div class="space-y-2">
                    <label class="text-[10px] font-black text-slate-500 uppercase tracking-widest ml-1">Category</label>
                    <select id="news_category" class="w-full bg-white/5 border border-white/10 rounded-2xl px-6 py-4 text-white focus:outline-none focus:border-blue-500 transition-all font-bold">
                        <option value="General">General</option>
                        <option value="Technology">Technology</option>
                        <option value="Politics">Politics</option>
                        <option value="Sports">Sports</option>
                        <option value="Entertainment">Entertainment</option>
                    </select>
                </div>
                <button onclick="NewsModule.addNews()" class="w-full bg-blue-500 hover:bg-blue-600 text-white font-black py-4 rounded-2xl shadow-lg shadow-blue-500/20 transition-all active:scale-[0.98]">
                    SAVE ARTICLE
                </button>
            </div>
        `;
        UI.modal.show('Add News Article', content);
    }
};
