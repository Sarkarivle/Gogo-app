const jwt = require('jsonwebtoken');
const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';
const { normalize } = require('../utils/phoneUtils');

const isAdmin = (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        if (!token) return res.status(401).json({ success: false, message: "Access denied." });

        const decoded = jwt.verify(token, JWT_SECRET);
        if (!decoded.role) {
            const url = req.originalUrl;
            if (!url.includes('/api/admin/stats') && !url.includes('/api/admin/users')) {
                 console.warn(`🔐 Admin Auth Warning: User ${decoded.phone || 'Unknown'} blocked from ${url}`);
            }
            return res.status(403).json({ success: false, message: "Admin privileges required." });
        }

        req.admin = decoded;
        next();
    } catch (error) {
        res.status(401).json({ success: false, message: "Invalid token." });
    }
};

const isUser = (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        if (!token) return res.status(401).json({ success: false, message: "Authentication required." });

        const decoded = jwt.verify(token, JWT_SECRET);
        req.user = decoded;

        if (decoded.role) return next();

        const url = req.originalUrl;
        if (url.includes('/track-event') || (req.method === 'GET' && url.includes('/profile/'))) {
            return next();
        }

        const userPhone = normalize(decoded.phone);
        const sensitiveMethods = ['POST', 'PUT', 'DELETE', 'PATCH'];
        let requestedPhone = req.params.phone || req.body.phone || req.query.phone;

        if (!requestedPhone && req.headers['content-type']?.includes('multipart/form-data')) {
            requestedPhone = req.query.phone;
        }

        if (requestedPhone && sensitiveMethods.includes(req.method)) {
            const tP = normalize(requestedPhone);
            if (userPhone !== tP && !url.includes('/report')) {
                return res.status(403).json({ success: false, message: "Unauthorized operation." });
            }
        } else if (url.includes('/history/') || url.includes('/check-block/')) {
            const parts = url.split('/');
            const p1 = normalize(parts[parts.length - 2]);
            const p2 = normalize(parts[parts.length - 1]?.split('?')[0]);
            if (userPhone !== p1 && userPhone !== p2) {
                return res.status(403).json({ success: false, message: "Unauthorized." });
            }
        }

        next();
    } catch (error) {
        res.status(401).json({ success: false, message: "Invalid session." });
    }
};

module.exports = {
    isAdmin,
    isUser
};
