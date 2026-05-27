const normalize = (p) => {
    if (!p) return '';
    const clean = String(p).replace(/[^0-9]/g, '');
    return clean.length >= 10 ? clean.slice(-10) : clean;
};

// Helper for DB query to match phone flexibly (exact or last 10)
const phoneQuery = (p) => {
    const n = normalize(p);
    return { $or: [{ phone: n }, { phone: new RegExp(n + '$') }] };
};

module.exports = { normalize, phoneQuery };
