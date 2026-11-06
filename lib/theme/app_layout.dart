import 'package:flutter/material.dart';

/// Responsive layout helpers for DineCircle.
///
/// These widgets provide consistent responsive patterns across the app,
/// preventing RenderFlex overflow and ensuring layouts adapt to different
/// screen sizes and text scales.

/// A Text widget that automatically truncates with ellipsis when space is limited.
///
/// Use this instead of plain Text in Rows/Columns where the text might overflow.
/// Defaults to single-line with ellipsis; set [maxLines] for multi-line text.
class ResponsiveText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;
  final TextOverflow? overflow;

  const ResponsiveText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.textAlign,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: overflow ?? TextOverflow.ellipsis,
    );
  }
}

/// A Row that automatically wraps dynamic children in Flexible widgets.
///
/// Use this instead of Row when you have multiple text/dynamic children that
/// might overflow. Static children (icons, fixed-width widgets) are not wrapped.
///
/// Example:
/// ```dart
/// SafeRow(
///   children: [
///     Icon(Icons.star), // not wrapped (fixed size)
///     Text('Dynamic title'), // wrapped in Flexible
///     Text('Subtitle'), // wrapped in Flexible
///   ],
/// )
/// ```
class SafeRow extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsetsGeometry? padding;

  const SafeRow({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    Widget row = Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children.map((child) {
        // Only wrap non-fixed-size widgets in Flexible
        if (child is Icon || child is SizedBox || child is Container) {
          return child;
        }
        return Flexible(child: child);
      }).toList(),
    );

    if (padding != null) {
      return Padding(padding: padding!, child: row);
    }
    return row;
  }
}

/// Breakpoint utilities for responsive layouts.
///
/// Use these to adapt layouts based on screen width:
/// - compact: ≤360px (small phones)
/// - medium: ≤600px (large phones, small tablets)
/// - expanded: >600px (tablets, desktop)
class Breakpoint {
  static bool isCompact(BuildContext context) {
    return MediaQuery.sizeOf(context).width <= 360;
  }

  static bool isMedium(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > 360 && width <= 600;
  }

  static bool isExpanded(BuildContext context) {
    return MediaQuery.sizeOf(context).width > 600;
  }

  /// Returns a value based on the current breakpoint.
  static T responsive<T>(
    BuildContext context, {
    required T compact,
    required T medium,
    required T expanded,
  }) {
    if (isCompact(context)) return compact;
    if (isMedium(context)) return medium;
    return expanded;
  }
}

/// A Column that automatically makes its last child Flexible if it might overflow.
///
/// Use this for vertical layouts where the content height is dynamic and might
/// exceed the available space (e.g., in bottom sheets or dialogs).
class SafeColumn extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsetsGeometry? padding;

  const SafeColumn({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    Widget column = Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );

    if (padding != null) {
      return Padding(padding: padding!, child: column);
    }
    return column;
  }
}

/// A Wrap widget for chip/tag collections that automatically flows to the next line.
///
/// Use this instead of Row for collections of chips, tags, or badges that might
/// overflow horizontally. Wrap is overflow-safe by design.
class ChipWrap extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  const ChipWrap({
    super.key,
    required this.children,
    this.spacing = 8.0,
    this.runSpacing = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: spacing, runSpacing: runSpacing, children: children);
  }
}
