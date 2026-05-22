const PaymentProvider = require('./PaymentProvider');
const https = require('https');
const crypto = require('crypto');

class CashfreeProvider extends PaymentProvider {
    constructor(config) {
        super(config);
        this.appId = config.appId;
        this.secretKey = config.secretKey;
        this.env = config.env || 'SANDBOX';
        this.host = this.env === 'PROD' ? 'api.cashfree.com' : 'sandbox.cashfree.com';
    }

    async createOrder({ phone, amount }) {
        const orderId = "ORD" + Date.now();
        const data = {
            order_amount: amount,
            order_id: orderId,
            order_currency: "INR",
            customer_details: {
                customer_id: "USER_" + phone,
                customer_phone: phone,
                customer_email: phone + "@gogoapp.com"
            },
            order_meta: {
                return_url: "https://api.gogoapp.com/api/payment/verify-cashfree?order_id={order_id}"
            }
        };

        const options = {
            hostname: this.host,
            path: '/pg/orders',
            method: 'POST',
            headers: {
                'x-client-id': this.appId,
                'x-client-secret': this.secretKey,
                'x-api-version': '2023-08-01',
                'Content-Type': 'application/json'
            }
        };

        return new Promise((resolve, reject) => {
            const req = https.request(options, (res) => {
                let body = '';
                res.on('data', (chunk) => body += chunk);
                res.on('end', () => {
                    try {
                        const result = JSON.parse(body);
                        if (result.order_status === 'ACTIVE' || result.payment_session_id) {
                            resolve({
                                success: true,
                                gateway: 'cashfree',
                                orderId: result.order_id,
                                order_session_id: result.payment_session_id,
                                env: this.env
                            });
                        } else {
                            reject(new Error(result.message || "Failed to create Cashfree order"));
                        }
                    } catch (e) {
                        reject(new Error("Invalid response from Cashfree"));
                    }
                });
            });
            req.on('error', (e) => reject(e));
            req.write(JSON.stringify(data));
            req.end();
        });
    }

    async verifyPayment({ order_id }) {
        const options = {
            hostname: this.host,
            path: `/pg/orders/${order_id}`,
            method: 'GET',
            headers: {
                'x-client-id': this.appId,
                'x-client-secret': this.secretKey,
                'x-api-version': '2023-08-01'
            }
        };

        return new Promise((resolve, reject) => {
            const req = https.request(options, (res) => {
                let body = '';
                res.on('data', (chunk) => body += chunk);
                res.on('end', () => {
                    try {
                        const result = JSON.parse(body);
                        if (result.order_status === 'PAID') {
                            resolve({ success: true, transactionId: result.cf_order_id });
                        } else {
                            reject(new Error(`Payment status: ${result.order_status}`));
                        }
                    } catch (e) {
                        reject(new Error("Invalid response from Cashfree"));
                    }
                });
            });
            req.on('error', (e) => reject(e));
            req.end();
        });
    }

    async handleWebhook(payload, signature) {
        // Cashfree webhook verification
        const timestamp = payload.timestamp;
        const rawBody = payload.rawBody; // Need to pass raw body from controller
        const data = timestamp + rawBody;
        const expectedSignature = crypto
            .createHmac('sha256', this.secretKey)
            .update(data)
            .digest('base64');

        if (expectedSignature !== signature) {
            throw new Error("Invalid Cashfree webhook signature");
        }

        const body = JSON.parse(rawBody);
        return {
            event: body.type,
            orderId: body.data.order.order_id,
            status: body.type === 'PAYMENT_SUCCESS_WEBHOOK' ? 'SUCCESS' : 'FAILED',
            raw: body
        };
    }
}

module.exports = CashfreeProvider;
