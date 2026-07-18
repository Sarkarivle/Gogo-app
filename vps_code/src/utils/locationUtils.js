/**
 * Helper to calculate numeric distance in KM
 */
function getDistanceKm(lat1, lon1, lat2, lon2) {
    try {
        const p1Lat = parseFloat(lat1);
        const p1Lon = parseFloat(lon1);
        const p2Lat = parseFloat(lat2);
        const p2Lon = parseFloat(lon2);
        if (isNaN(p1Lat) || isNaN(p1Lon) || isNaN(p2Lat) || isNaN(p2Lon)) return null;

        const R = 6371; // Radius of earth in KM
        const dLat = (p2Lat - p1Lat) * Math.PI / 180;
        const dLon = (p2Lon - p1Lon) * Math.PI / 180;
        const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                  Math.cos(p1Lat * Math.PI / 180) * Math.cos(p2Lat * Math.PI / 180) *
                  Math.sin(dLon / 2) * Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    } catch (e) {
        return null;
    }
}

/**
 * Helper to format distance string for privacy
 */
function formatDistanceString(d) {
    if (d === null) return "";
    if (d < 0.5) return "0.5 km";
    if (d < 1) return "Within 1 km";
    if (d < 5) return "Under 5 km";
    return d.toFixed(1) + " km";
}

/**
 * Combined helper to calculate and format distance
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
    return formatDistanceString(getDistanceKm(lat1, lon1, lat2, lon2));
}

module.exports = {
    getDistanceKm,
    formatDistanceString,
    calculateDistance
};
