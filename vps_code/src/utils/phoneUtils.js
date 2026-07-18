const normalize = (p) => {
    if (!p) return '';
    const clean = String(p).replace(/[^0-9]/g, '');
    return clean.length >= 10 ? clean.slice(-10) : clean;
};

// Helper for DB query to match phone flexibly (exact or common variations)
// Optimized: Using $in instead of RegExp to allow MongoDB to use indexes efficiently.
const phoneQuery = (p) => {
    const n = normalize(p);
    return { phone: { $in: [n, `+91${n}`, `91${n}`] } };
};

module.exports = { normalize, phoneQuery };
