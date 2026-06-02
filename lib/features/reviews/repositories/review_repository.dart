import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gogo/core/api/api_service.dart';
import 'package:gogo/features/reviews/models/user_review.dart';

class ReviewRepository {
  static final ReviewRepository _instance = ReviewRepository._internal();
  factory ReviewRepository() => _instance;
  ReviewRepository._internal();

  Future<bool> submitReview(UserReview review) async {
    try {
      final response = await ApiService.post('/api/review/submit', review.toJson());
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Submit review error: $e');
      return false;
    }
  }

  Future<List<UserReview>> getReviews(String phone) async {
    try {
      final response = await ApiService.get('/api/review/list/$phone');
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> list = data['reviews'] ?? [];
          return list.map((item) => UserReview.fromJson(item)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Get reviews error: $e');
      return [];
    }
  }
}
