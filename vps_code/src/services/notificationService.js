const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const serviceAccountPath = path.join(__dirname, '../../serviceAccountKey.json');

if (fs.existsSync(serviceAccountPath)) {
    try {
        if (!admin.apps.length) {
            const serviceAccount = require(serviceAccountPath);
            admin.initializeApp({
                credential: admin.credential.cert(serviceAccount)
            });
            console.log("✅ Firebase Admin Initialized Successfully");
        }
    } catch (e) {
        console.error("❌ Firebase Init Error:", e.message);
    }
} else {
    console.log("⚠️ Firebase serviceAccountKey.json not found. Push notifications will be skipped.");
}

exports.sendPushNotification = async (token, title, body, extraData = {}) => {
    if (!admin.apps.length || !token) {
        return;
    }

    const dataPayload = {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        type: "chat", // Default to chat to maintain backward compatibility
        ...extraData
    };

    // FCM requires all data values to be strings
    Object.keys(dataPayload).forEach(key => {
        if (dataPayload[key] !== null && dataPayload[key] !== undefined) {
            dataPayload[key] = String(dataPayload[key]);
        }
    });

    const message = {
        notification: { title, body },
        data: dataPayload,
        android: {
            priority: 'high',
            notification: {
                channelId: 'chat_messages', // Flutter app channel ID
                priority: 'max',
                sound: 'default'
            }
        },
        apns: {
            payload: {
                aps: { contentAvailable: true, sound: 'default' }
            }
        },
        token: token
    };

    try {
        const response = await admin.messaging().send(message);
        console.log("🚀 FCM Success:", response);
        return true;
    } catch (error) {
        console.error("❌ FCM Error:", error.message);
        return false;
    }
};
