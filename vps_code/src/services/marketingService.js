const axios = require('axios');
const MarketingConfig = require('../models/MarketingConfig');

class MarketingService {
    async getGlobalConfig() {
        let config = await MarketingConfig.findOne({ key: 'global_settings' });
        if (!config) {
            config = new MarketingConfig({ key: 'global_settings' });
            await config.save();
        }
        return config;
    }

    async triggerS2SPostback(type, clickId, value = 0) {
        try {
            const config = await this.getGlobalConfig();
            if (!config.isTrackingEnabled) return;

            let urlTemplate = '';
            if (type === 'install') urlTemplate = config.installPostbackUrl;
            else if (type === 'registration') urlTemplate = config.registrationPostbackUrl;
            else if (type === 'purchase') urlTemplate = config.purchasePostbackUrl;

            if (!urlTemplate) return;

            // Replace placeholders: {clickid}, {value}
            let finalUrl = urlTemplate
                .replace(/{clickid}/g, clickId || '')
                .replace(/{value}/g, value.toString());

            console.log(`📡 [Marketing] Triggering ${type} S2S Postback: ${finalUrl}`);

            await axios.get(finalUrl, { timeout: 5000 });
            console.log(`✅ [Marketing] S2S Postback successful for ${type}`);

        } catch (err) {
            console.error(`❌ [Marketing] S2S Postback failed for ${type}:`, err.message);
        }
    }
}

module.exports = new MarketingService();
