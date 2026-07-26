class PaymentProvider {
    constructor(config) {
        this.config = config;
    }

    async createOrder(data) {
        throw new Error("createOrder() must be implemented");
    }

    async verifyPayment(data) {
        throw new Error("verifyPayment() must be implemented");
    }

    async handleWebhook(data, signature) {
        throw new Error("handleWebhook() must be implemented");
    }
}

module.exports = PaymentProvider;
