const mongoose = require('mongoose');

const connectDB = async () => {
    try {
        const MONGO_URI = process.env.MONGO_URI || "mongodb://localhost:27017/gogo";
        const options = {
            maxPoolSize: 100, // Maintain up to 100 socket connections
            minPoolSize: 10,  // Keep at least 10 connections open
            socketTimeoutMS: 45000, // Close sockets after 45 seconds of inactivity
            family: 4 // Use IPv4, skip trying IPv6
        };
        const conn = await mongoose.connect(MONGO_URI, options);
        console.log(`🚀 High-Performance DB Connected: ${conn.connection.host}`);
    } catch (error) {
        console.error(`❌ Error: ${error.message}`);
        process.exit(1);
    }
};

module.exports = connectDB;
