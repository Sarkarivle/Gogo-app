const mongoose = require('mongoose');
const dotenv = require('dotenv');
const path = require('path');
const fs = require('fs');

dotenv.config();

const Config = require('./src/models/Config');

const gpKey = JSON.parse(fs.readFileSync(path.join(__dirname, 'gp_service_account.json'), 'utf8'));

async function updateConfig() {
    try {
        await mongoose.connect(process.env.MONGO_URI);
        console.log("Connected to MongoDB");

        await Config.findOneAndUpdate(
            { key: 'google_play_settings' },
            {
                value: {
                    isEnabled: true,
                    serviceAccountKey: gpKey
                },
                updatedAt: new Date()
            },
            { upsert: true }
        );

        console.log("✅ Google Play Settings updated successfully in Database!");
        process.exit(0);
    } catch (err) {
        console.error("❌ Error updating config:", err);
        process.exit(1);
    }
}

updateConfig();
