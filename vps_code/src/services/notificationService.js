const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const serviceAccountPaths = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
    process.env.GOOGLE_APPLICATION_CREDENTIALS,
    path.join(__dirname, '../../serviceAccountKey.json')
].filter(Boolean);

const serviceAccountPath = serviceAccountPaths.find(candidatePath => fs.existsSync(candidatePath));

if (serviceAccountPath) {
    try {
        if (!admin.apps.length) {
            const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

            if (serviceAccount.type !== 'service_account' || !serviceAccount.client_email || !serviceAccount.private_key) {
                throw new Error('Firebase Admin service account required. google-services.json is Android client config, not a backend key.');
            }

            admin.initializeApp({
                credential: admin.credential.cert(serviceAccount)
            });
            console.log(`✅ Firebase Admin Initialized Successfully (${serviceAccountPath})`);
        }
    } catch (e) {
        console.error("❌ Firebase Init Error:", e.message);
    }
} else {
    console.log(`⚠️ Firebase Admin service account not found. Checked: ${serviceAccountPaths.join(', ')}. Push notifications will be skipped.`);
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
        return { success: true, response };
    } catch (error) {
        console.error("❌ FCM Error:", error.message);
        // Return structured error so caller can cleanup if token is invalid
        return {
            success: false,
            error: error.message,
            isInvalidToken: error.code === 'messaging/registration-token-not-registered' ||
                            error.code === 'messaging/invalid-registration-token' ||
                            error.message.includes('not found')
        };
    }
};
