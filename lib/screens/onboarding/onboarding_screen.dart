import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';

/// Onboarding screen with slides
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingSlide> _slides = [
    const _OnboardingSlide(
      icon: Icons.restaurant_menu_rounded,
      title: 'Host Dining Experiences',
      description: 'Create exclusive tasting nights, chef tables, and special menus at top restaurants. Turn your food knowledge into unforgettable events.',
    ),
    const _OnboardingSlide(
      icon: Icons.attach_money_rounded,
      title: 'Monetize Your Audience',
      description: 'Turn your followers into a paying dining community. Earn revenue from every seat filled at your events.',
    ),
    const _OnboardingSlide(
      icon: Icons.handshake_rounded,
      title: 'Partner with Restaurants',
      description: 'Collaborate with restaurants for sponsored experiences, exclusive menus, and mutually beneficial partnerships.',
    ),
    const _OnboardingSlide(
      icon: Icons.groups_rounded,
      title: 'Grow Your Community',
      description: 'Meet followers in person, attract new audiences through public dinners, and build a loyal food community.',
    ),
    const _OnboardingSlide(
      icon: Icons.analytics_rounded,
      title: 'Track Your Impact',
      description: 'Analytics for views, bookings, attendance, revenue, and engagement. Build credibility through ratings and reviews.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: widget.onComplete,
                child: Text(
                  'Skip',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            // Slides
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.primaryGradient,
                            ),
                            child: Icon(
                              slide.icon,
                              size: 70,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          // Title
                          Text(
                            slide.title,
                            style: AppTextStyles.displayMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          // Description
                          Text(
                            slide.description,
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Indicators and button
            Padding(
              padding: const EdgeInsets.all(AppSpacing.paddingScreen),
              child: Column(
                children: [
                  // Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => Container(
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? AppColors.primary
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Next button
                  PrimaryButton(
                    text: _currentPage == _slides.length - 1
                        ? 'Get Started'
                        : 'Next',
                    onPressed: _nextPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}
