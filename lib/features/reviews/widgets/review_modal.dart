import 'package:flutter/material.dart';
import 'package:gogo/features/reviews/models/user_review.dart';
import 'package:gogo/features/reviews/repositories/review_repository.dart';

class ReviewModal extends StatefulWidget {
  final String reviewerPhone;
  final String reviewerName;
  final String reviewedPhone;
  final String reviewedName;

  const ReviewModal({
    super.key,
    required this.reviewerPhone,
    required this.reviewerName,
    required this.reviewedPhone,
    required this.reviewedName,
  });

  static void show(BuildContext context, {
    required String reviewerPhone,
    required String reviewerName,
    required String reviewedPhone,
    required String reviewedName,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReviewModal(
        reviewerPhone: reviewerPhone,
        reviewerName: reviewerName,
        reviewedPhone: reviewedPhone,
        reviewedName: reviewedName,
      ),
    );
  }

  @override
  State<ReviewModal> createState() => _ReviewModalState();
}

class _ReviewModalState extends State<ReviewModal> {
  String _selectedType = 'good'; // 'good' or 'bad'
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final review = UserReview(
      reviewerPhone: widget.reviewerPhone,
      reviewerName: widget.reviewerName,
      reviewedPhone: widget.reviewedPhone,
      type: _selectedType,
      comment: _commentController.text.trim(),
      timestamp: DateTime.now(),
    );

    final success = await ReviewRepository().submitReview(review);
    
    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your feedback!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit review. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),
              Text(
                '${widget.reviewedName} ke saath baat karke kaisa laga?',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTypeOption('good', 'Achha laga', Icons.sentiment_very_satisfied_rounded, Colors.greenAccent),
                  _buildTypeOption('bad', 'Bura laga', Icons.sentiment_very_dissatisfied_rounded, Colors.redAccent),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _commentController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Apna anubhav likhein (optional)...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text('SUBMIT REVIEW', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeOption(String type, String label, IconData icon, Color color) {
    bool isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
            ),
            child: Icon(icon, color: isSelected ? color : Colors.white24, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: isSelected ? color : Colors.white54, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}
