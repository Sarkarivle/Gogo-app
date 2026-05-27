const UI = {
    loader() {
        return '<div class="flex justify-center items-center h-full py-20 text-[10px] font-black uppercase opacity-20 tracking-[0.3em] animate-pulse text-white">Synchronizing Data...</div>';
    },

    skeletonCard() {
        return `
            <div class="glass p-8 rounded-[2rem] space-y-4">
                <div class="skeleton h-3 w-20"></div>
                <div class="skeleton h-10 w-32"></div>
                <div class="skeleton h-3 w-24"></div>
            </div>
        `;
    },

    skeletonTable(rows = 5) {
        let rowHtml = '';
        for(let i=0; i<rows; i++) {
            rowHtml += `
                <tr class="border-b border-white/5">
                    <td class="p-6"><div class="skeleton h-4 w-12"></div></td>
                    <td class="p-6"><div class="skeleton h-4 w-32"></div></td>
                    <td class="p-6"><div class="skeleton h-4 w-20"></div></td>
                    <td class="p-6"><div class="skeleton h-4 w-24"></div></td>
                    <td class="p-6"><div class="skeleton h-8 w-16 rounded-full"></div></td>
                </tr>
            `;
        }
        return `
            <div class="glass rounded-[2.5rem] overflow-hidden animate-fade">
                <table class="w-full text-left">
                    <thead class="bg-white/5 border-b border-white/5">
                        <tr>
                            <th class="p-6"><div class="skeleton h-3 w-8"></div></th>
                            <th class="p-6"><div class="skeleton h-3 w-20"></div></th>
                            <th class="p-6"><div class="skeleton h-3 w-16"></div></th>
                            <th class="p-6"><div class="skeleton h-3 w-24"></div></th>
                            <th class="p-6"><div class="skeleton h-3 w-12"></div></th>
                        </tr>
                    </thead>
                    <tbody>${rowHtml}</tbody>
                </table>
            </div>
        `;
    },

    skeletonGrid(count = 6) {
        let gridHtml = '';
        for(let i=0; i<count; i++) {
            gridHtml += `
                <div class="glass p-6 rounded-[2rem] space-y-4">
                    <div class="flex justify-between">
                        <div class="skeleton h-4 w-32"></div>
                        <div class="skeleton h-4 w-16 rounded-full"></div>
                    </div>
                    <div class="skeleton h-64 w-full rounded-2xl"></div>
                    <div class="flex space-x-2">
                        <div class="skeleton h-10 flex-1"></div>
                        <div class="skeleton h-10 w-12"></div>
                    </div>
                </div>
            `;
        }
        return `<div class="grid grid-cols-3 gap-6">${gridHtml}</div>`;
    },

    skeletonMediaGrid(count = 10) {
        let gridHtml = '';
        for(let i=0; i<count; i++) {
            gridHtml += `<div class="aspect-square skeleton rounded-[2.5rem]"></div>`;
        }
        return `
            <div class="glass p-10 rounded-[3rem] space-y-8 animate-fade">
                <div class="flex justify-between items-center mb-8">
                    <div class="skeleton h-10 w-64"></div>
                    <div class="skeleton h-10 w-48 rounded-2xl"></div>
                </div>
                <div class="grid grid-cols-5 gap-6">${gridHtml}</div>
            </div>
        `;
    },

    skeletonModal() {
        return `
            <div class="space-y-6 animate-fade">
                <div class="skeleton h-6 w-1/2 mb-4"></div>
                <div class="grid grid-cols-2 gap-4">
                    <div class="skeleton h-16 w-full rounded-2xl"></div>
                    <div class="skeleton h-16 w-full rounded-2xl"></div>
                </div>
                <div class="skeleton h-24 w-full rounded-2xl"></div>
                <div class="skeleton h-12 w-full rounded-2xl"></div>
            </div>
        `;
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
