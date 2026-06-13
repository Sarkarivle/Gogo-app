const mongoose = require('mongoose');

const connectDB = async () => {
    try {
        const MONGO_URI = process.env.MONGO_URI || "mongodb://localhost:27017/gogo";
        const options = {
            maxPoolSize: 500, // Increased for M10 Tier (Screenshot showed 127/100 limit hit)
            minPoolSize: 20,
            socketTimeoutMS: 60000,
            serverSelectionTimeoutMS: 10000,
            heartbeatFrequencyMS: 10000,
            family: 4
        };
        const conn = await mongoose.connect(MONGO_URI, options);
        console.log(`🚀 High-Performance DB Connected: ${conn.connection.host}`);
    } catch (error) {
        console.error(`❌ Error: ${error.message}`);
        process.exit(1);
    }
};

module.exports = connectDB;
