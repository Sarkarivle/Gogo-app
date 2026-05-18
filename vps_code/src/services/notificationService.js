const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const serviceAccountPath = path.join(__dirname, '../../serviceAccountKey.json');

if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = require(serviceAccountPath);
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
    console.log("✅ Firebase Admin Initialized");
} else {
    console.log("⚠️ Firebase serviceAccountKey.json not found. Push notifications will be skipped.");
}

exports.sendPushNotification = async (token, title, body, extraData = {}) => {
    if (!admin.apps.length || !token) return;

    const message = {
        notification: { title, body },
        data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            type: "chat",
            ...extraData
        },
        token: token
    };

    try {
        await admin.messaging().send(message);
        console.log("🚀 Notification sent to:", token);
    } catch (error) {
        console.log("❌ Firebase Send Error:", error.message);
    }
};
