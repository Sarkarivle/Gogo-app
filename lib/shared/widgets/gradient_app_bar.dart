import 'package:flutter/material.dart';

/// Shared light header gradient used across the app (white -> soft pink -> white),
/// matching the home screen's header treatment.
const LinearGradient kAppHeaderGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Colors.white, Color(0xFFF3C7DB), Colors.white],
  stops: [0.0, 0.5, 1.0],
);

/// Drop-in replacement for AppBar(...) that paints the shared wine-to-black
/// header gradient instead of a flat color. Accepts the same common params.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final double elevation;

  const GradientAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
    this.elevation = 0,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle,
      elevation: elevation,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: kAppHeaderGradient),
      ),
    );
  }
}
