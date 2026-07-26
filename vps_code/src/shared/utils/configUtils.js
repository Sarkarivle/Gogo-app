/**
 * Shared Logic to determine if user should be in Standard Mode (Review Mode)
 * @param {Object} user User object
 * @param {Object} config Review mode config object
 * @returns {boolean}
 */
function determineStandardMode(user, config) {
    // Google Compliance logic removed.
    return false;
}

module.exports = {
    determineStandardMode
};
