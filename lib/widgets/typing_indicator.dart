import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Animated three-dot typing indicator.
///
/// Each dot bounces in sequence with a staggered delay, producing the
/// familiar "someone is typing…" effect. The animation loops indefinitely
/// while the widget is mounted.
class TypingIndicator extends StatefulWidget {
  final Color dotColor;
  final double dotSize;

  const TypingIndicator({
    super.key,
    this.dotColor = AppColors.textSecondary,
    this.dotSize = 6,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(
            delay: 0.0,
            controller: _controller,
            color: widget.dotColor,
            size: widget.dotSize,
          ),
          SizedBox(width: widget.dotSize * 0.5),
          _Dot(
            delay: 0.2,
            controller: _controller,
            color: widget.dotColor,
            size: widget.dotSize,
          ),
          SizedBox(width: widget.dotSize * 0.5),
          _Dot(
            delay: 0.4,
            controller: _controller,
            color: widget.dotColor,
            size: widget.dotSize,
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.delay,
    required this.controller,
    required this.color,
    required this.size,
  });

  final double delay;
  final AnimationController controller;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = (controller.value - delay).clamp(0.0, 1.0);
    final y = _bounce(t);
    return Transform.translate(
      offset: Offset(0, -y * size * 0.8),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.4 + 0.6 * y),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  double _bounce(double t) {
    if (t < 0.5) return t * 2;
    return 2 - t * 2;
  }
}

/// Inline text label shown above the composer: "Alex is typing…"
class TypingBanner extends StatelessWidget {
  final List<String> names;

  const TypingBanner({super.key, required this.names});

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final text = names.length == 1
        ? '${names.first} is typing'
        : names.length == 2
            ? '${names.first} and ${names[1]} are typing'
            : '${names.first} and ${names.length - 1} others are typing';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TypingIndicator(dotSize: 5),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
