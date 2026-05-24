const mongoose = require('mongoose');

const NewsArticleSchema = new mongoose.Schema({
    title: { type: String, required: true },
    source: { type: String, required: true },
    image_url: { type: String },
    destination_url: { type: String, required: true },
    category: { type: String, default: 'General' },
    published_at: { type: Date, default: Date.now },
    is_active: { type: Boolean, default: true },
    sort_order: { type: Number, default: 0 },
    created_at: { type: Date, default: Date.now },
    updated_at: { type: Date, default: Date.now }
});

NewsArticleSchema.pre('save', function(next) {
    this.updated_at = Date.now();
    next();
});

module.exports = mongoose.model('NewsArticle', NewsArticleSchema);
