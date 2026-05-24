import 'dart:convert';
import 'api_service.dart';
import '../models/news_article.dart';

class NewsRepository {
  static final NewsRepository _instance = NewsRepository._internal();
  factory NewsRepository() => _instance;
  NewsRepository._internal();

  Future<List<NewsArticle>> getNews({int page = 1, int limit = 10}) async {
    try {
      final response = await ApiService.get('/api/user/news/public?page=$page&limit=$limit');
      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        if (body['success'] == true) {
          final List newsData = body['data'];
          return newsData.map((json) => NewsArticle.fromJson(json)).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching news: $e');
      return [];
    }
  }
}
