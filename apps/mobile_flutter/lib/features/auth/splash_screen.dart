import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/widgets/brand_mark.dart';
import 'welcome_screen.dart' show brandHeroTag;

/// Shown while the app starts: only the symbol, easing in. It shares a Hero
/// with the welcome screen, so the symbol moves into place when that opens.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _c,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1).animate(curve),
            child: Hero(tag: brandHeroTag, child: const BrandMark(size: 120)),
          ),
        ),
      ),
    );
  }
}
