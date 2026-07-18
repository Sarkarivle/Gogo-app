class NewsArticle {
  final String id;
  final String title;
  final String source;
  final String? imageUrl;
  final String destinationUrl;
  final String category;
  final DateTime publishedAt;

  NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    this.imageUrl,
    required this.destinationUrl,
    required this.category,
    required this.publishedAt,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      source: json['source'] ?? '',
      imageUrl: json['image_url'],
      destinationUrl: json['destination_url'] ?? '',
      category: json['category'] ?? 'General',
      publishedAt: DateTime.parse(json['published_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}
