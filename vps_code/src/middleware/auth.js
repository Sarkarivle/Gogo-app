// Placeholder for future authentication middleware
// You can add JWT verification here for secure APIs

exports.isAdmin = (req, res, next) => {
    // For now, let it pass. In production, check for admin token.
    next();
};

exports.isUser = (req, res, next) => {
    next();
};
