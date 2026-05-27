const jwt = require('jsonwebtoken');
const JWT_SECRET = process.env.JWT_SECRET || 'GOGO_ADMIN_SUPER_SECRET_2024';

exports.isAdmin = (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        if (!token) return res.status(401).json({ success: false, message: "Access denied." });
        const decoded = jwt.verify(token, JWT_SECRET);
        req.admin = decoded;
        next();
    } catch (error) {
        res.status(401).json({ success: false, message: "Invalid token." });
    }
};

exports.isUser = (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        if (!token) return res.status(401).json({ success: false, message: "Authentication required." });

        const decoded = jwt.verify(token, JWT_SECRET);
        req.user = decoded;

        const url = req.originalUrl;

        // Skip IDOR check for public/tracking/profile-read endpoints
        if (url.includes('/track-event') || (req.method === 'GET' && url.includes('/profile/'))) {
            return next();
        }

        const userPhone = String(decoded.phone).replace(/[^0-9]/g, '');

        // Optimized IDOR check
        let requestedPhone = req.params.phone || req.body.phone || req.query.phone;

        if (requestedPhone) {
            const tP = String(requestedPhone).replace(/[^0-9]/g, '');
            if (userPhone !== tP && !userPhone.endsWith(tP) && !tP.endsWith(userPhone)) {
                return res.status(403).json({ success: false, message: "Unauthorized." });
            }
        } else if (url.includes('/history/') || url.includes('/check-block/')) {
            const parts = url.split('/');
            // Extract phones from /api/chat/history/:p1/:p2
            const p1 = String(parts[parts.length - 2]).replace(/[^0-9]/g, '');
            const p2 = String(parts[parts.length - 1]?.split('?')[0]).replace(/[^0-9]/g, '');

            if (userPhone !== p1 && userPhone !== p2) {
                return res.status(403).json({ success: false, message: "Unauthorized." });
            }
        } else if (url.includes('/upload')) {
            // Ensure phone in upload matches decoded token
            const uploadPhone = String(req.body.phone || req.query.phone || '').replace(/[^0-9]/g, '');
            if (uploadPhone && userPhone !== uploadPhone) {
                return res.status(403).json({ success: false, message: "Unauthorized upload." });
            }
        }

        next();
    } catch (error) {
        res.status(401).json({ success: false, message: "Invalid session." });
    }
};
