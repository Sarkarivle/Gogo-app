import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:gogo/shared/widgets/blinking_dot.dart';

class HomeFilterChip extends StatelessWidget {
  final String label;
  final bool hasDropdown;
  final bool isLive;
  final VoidCallback? onTap;

  const HomeFilterChip({
    super.key,
    required this.label,
    this.hasDropdown = true,
    this.isLive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (isLive) ...[
              const BlinkingDot(),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (hasDropdown) ...[
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded, size: 18, color: Colors.white70),
            ],
          ],
        ),
      ),
    );
  }
}

class FilterDialog extends StatelessWidget {
  final String title;
  final List<String> options;
  final String currentValue;
  final Function(String) onSelect;

  const FilterDialog({
    super.key,
    required this.title,
    required this.options,
    required this.currentValue,
    required this.onSelect,
  });

  static void show(BuildContext context, String title, List<String> options, String currentValue, Function(String) onSelect) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: FadeTransition(
              opacity: anim1,
              child: FilterDialog(
                title: title,
                options: options,
                currentValue: currentValue,
                onSelect: onSelect,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E).withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Colors.white10),
      ),
      title: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (context, index) {
            final option = options[index];
            final bool isSelected = option == currentValue;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    onSelect(option);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: isSelected ? Colors.orangeAccent.withValues(alpha: 0.3) : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        Text(
                          option,
                          style: TextStyle(
                            color: isSelected ? Colors.orangeAccent : Colors.white,
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.orangeAccent, size: 22),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
