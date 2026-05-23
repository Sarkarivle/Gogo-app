const UI = {
    loader() {
        return '<div class="flex justify-center items-center h-full"><div class="custom-loader"></div></div>';
    },

    badge(text, colorClass = 'bg-orange-500/10 text-orange-500') {
        return `<span class="px-3 py-1 rounded-full text-[9px] font-black uppercase ${colorClass}">${text}</span>`;
    },

    card(title, value, subtext = '', colorClass = 'text-white') {
        const id = title.toLowerCase().replace(/\s+/g, '-');
        return `
            <div class="glass p-8 rounded-[2rem]" data-card-id="${id}">
                <p class="text-[10px] font-black text-slate-500 uppercase mb-2">${title}</p>
                <h2 class="text-4xl font-black ${colorClass}">${value}</h2>
                ${subtext ? `<p class="text-[10px] text-slate-500 mt-2">${subtext}</p>` : ''}
            </div>
        `;
    },

    table(headers, rows) {
        return `
            <div class="glass rounded-[2.5rem] overflow-hidden animate-fade">
                <table class="w-full text-left">
                    <thead class="bg-white/5 border-b border-white/5 text-[10px] font-black uppercase text-slate-500">
                        <tr>${headers.map(h => `<th class="p-6">${h}</th>`).join('')}</tr>
                    </thead>
                    <tbody class="divide-y divide-white/5">
                        ${rows.length ? rows.join('') : '<tr><td colspan="${headers.length}" class="p-20 text-center opacity-20 uppercase font-bold tracking-widest">No data available</td></tr>'}
                    </tbody>
                </table>
            </div>
        `;
    },

    modal: {
        show(title, content) {
            document.getElementById('actionModal').classList.remove('hidden');
            document.getElementById('actionModal').classList.add('flex');
            document.getElementById('modalHeaderTitle').innerHTML = title;
            document.getElementById('modalBody').innerHTML = content;
        },
        hide() {
            document.getElementById('actionModal').classList.add('hidden');
            document.getElementById('actionModal').classList.remove('flex');
        },
        setDynamicContent(content) {
            document.getElementById('userControlDynamic').innerHTML = content;
        }
    }
};
