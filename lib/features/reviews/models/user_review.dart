class UserReview {
  final String? id;
  final String reviewerPhone;
  final String reviewerName;
  final String reviewedPhone;
  final String type; // 'good' or 'bad'
  final String comment;
  final DateTime timestamp;

  UserReview({
    this.id,
    required this.reviewerPhone,
    required this.reviewerName,
    required this.reviewedPhone,
    required this.type,
    required this.comment,
    required this.timestamp,
  });

  factory UserReview.fromJson(Map<String, dynamic> json) {
    return UserReview(
      id: json['_id'] ?? json['id'],
      reviewerPhone: json['reviewerPhone'],
      reviewerName: json['reviewerName'] ?? 'User',
      reviewedPhone: json['reviewedPhone'],
      type: json['type'] ?? 'good',
      comment: json['comment'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reviewerPhone': reviewerPhone,
      'reviewerName': reviewerName,
      'reviewedPhone': reviewedPhone,
      'type': type,
      'comment': comment,
    };
  }
}
