import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/brand_mark.dart';
import 'celebration_backdrop.dart';

/// Hero tag shared with the splash so the symbol glides into place.
const brandHeroTag = 'setzo-brand-mark';

/// First screen for a signed-out user: the symbol, one line, one round button.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted, this.onDebugPreviews});

  final VoidCallback onGetStarted;

  /// Debug builds only: opens the design previews.
  final VoidCallback? onDebugPreviews;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(
        children: [
          const CelebrationBackdrop(),
          if (onDebugPreviews != null)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(child: TextButton(onPressed: onDebugPreviews, child: const Text('Previews'))),
            ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 96),
                        const Hero(tag: brandHeroTag, child: BrandMark(size: 96)),
                        const SizedBox(height: AppSpace.m),
                        Text(
                          'SetzO',
                          style: text.displaySmall?.copyWith(
                            fontFamily: AppFonts.display,
                            color: AppColors.maroon,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: AppSpace.xl),
                        Semantics(
                          header: true,
                          child: Text(
                            'Every celebration begins with a plan.',
                            textAlign: TextAlign.center,
                            style: text.titleLarge?.copyWith(color: AppColors.maroon, fontStyle: FontStyle.italic),
                          ),
                        ),
                        const SizedBox(height: AppSpace.xxl),
                        _LetsGoButton(onPressed: onGetStarted),
                        const SizedBox(height: 72),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LetsGoButton extends StatelessWidget {
  const _LetsGoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Let's go",
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: AppColors.primary.withValues(alpha: 0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: const SizedBox.square(
              dimension: 72,
              child: Icon(Icons.arrow_forward_rounded, color: AppColors.onPrimary, size: 34),
            ),
          ),
        ),
      ),
    );
  }
}
