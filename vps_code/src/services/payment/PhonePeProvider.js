const PaymentProvider = require('./PaymentProvider');
const crypto = require('crypto');
const https = require('https');

class PhonePeProvider extends PaymentProvider {
    constructor(config) {
        super(config);
        this.merchantId = config.merchantId.trim();
        this.saltKey = config.saltKey.trim();
        this.saltIndex = config.saltIndex || "1";
        this.env = config.env || 'UAT';
        this.host = this.env === 'PROD' ? 'api.phonepe.com' : 'api-preprod.phonepe.com';
        this.pathPrefix = '/apis/hermes';
    }

    async createOrder({ phone, amount }) {
        const merchantTransactionId = "TXN" + Date.now();
        const payload = {
            merchantId: this.merchantId,
            merchantTransactionId: merchantTransactionId,
            merchantUserId: "U" + phone,
            amount: amount * 100, // paise
            callbackUrl: `https://api.gogoapp.com/api/payment/webhook/phonepe`,
            mobileNumber: phone,
            paymentInstrument: { type: "PAY_PAGE" }
        };

        const base64Payload = Buffer.from(JSON.stringify(payload)).toString('base64');
        const endpoint = "/pg/v1/pay";
        const checksum = crypto.createHash('sha256').update(base64Payload + endpoint + this.saltKey).digest('hex') + "###" + this.saltIndex;

        return {
            success: true,
            gateway: 'phonepe',
            orderId: merchantTransactionId,
            base64Payload,
            checksum,
            merchantId: this.merchantId,
            env: this.env
        };
    }

    async verifyPayment({ merchantTransactionId }) {
        const endpoint = `${this.pathPrefix}/pg/v1/status/${this.merchantId}/${merchantTransactionId}`;
        const checksum = crypto.createHash('sha256').update(endpoint + this.saltKey).digest('hex') + "###" + this.saltIndex;

        const options = {
            hostname: this.host,
            path: endpoint,
            method: 'GET',
            headers: {
                'accept': 'application/json',
                'Content-Type': 'application/json',
                'X-VERIFY': checksum,
                'X-MERCHANT-ID': this.merchantId
            }
        };

        return new Promise((resolve, reject) => {
            const req = https.request(options, (res) => {
                let data = '';
                res.on('data', (chunk) => data += chunk);
                res.on('end', () => {
                    try {
                        const response = JSON.parse(data);
                        if (response.success && response.code === 'PAYMENT_SUCCESS') {
                            resolve({ success: true, transactionId: response.data.transactionId });
                        } else {
                            reject(new Error(response.message || "PhonePe verification failed"));
                        }
                    } catch (e) {
                        reject(new Error("Invalid JSON response from PhonePe"));
                    }
                });
            });
            req.on('error', (e) => reject(e));
            req.end();
        });
    }

    async handleWebhook(payload, signature) {
        const base64Response = payload.response;
        const checksum = crypto.createHash('sha256').update(base64Response + this.saltKey).digest('hex') + "###" + this.saltIndex;

        if (checksum !== signature) {
            throw new Error("Invalid PhonePe webhook signature");
        }

        const decodedResponse = JSON.parse(Buffer.from(base64Response, 'base64').toString());
        return {
            event: 'payment.status',
            orderId: decodedResponse.data.merchantTransactionId,
            status: decodedResponse.success ? 'SUCCESS' : 'FAILED',
            raw: decodedResponse
        };
    }
}

module.exports = PhonePeProvider;
