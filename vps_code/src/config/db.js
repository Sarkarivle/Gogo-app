const mongoose = require('mongoose');

const connectDB = async () => {
    try {
        const MONGO_URI = "mongodb+srv://hpvkash_db_user:1XKHQlXrZemIXnUU@cluster0.7ia8pc3.mongodb.net/gogo?retryWrites=true&w=majority&appName=Cluster0";
        const conn = await mongoose.connect(MONGO_URI);
        console.log(`✅ MongoDB Connected: ${conn.connection.host}`);
    } catch (error) {
        console.error(`❌ Error: ${error.message}`);
        process.exit(1);
    }
};

module.exports = connectDB;
