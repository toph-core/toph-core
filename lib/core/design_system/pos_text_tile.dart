/// The tile the order flow is built from: a wide, short row carrying a name.
///
/// Both ordering grids use this — the categories on the first screen and the
/// meals on the second — so "the menu tiles match the category tiles" is true
/// by construction rather than by two widgets being kept in step by hand. They
/// were picture cards until an operator pointed out the obvious: almost nothing
/// in this venue's catalogue has an image, so four fifths of every tile was a
/// giant first letter, and the name — the only part anybody reads — was
/// squeezed into a clipped line underneath.
///
/// What survives of the visual identity is [accent], as a bar down the leading
/// edge. It is the one thing the old card had that told tiles apart at a glance
/// without costing the name any width.
library;

import 'package:flutter/material.dart';
import 'package:mary_ai_pos/core/design_system/pos_design_system.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';

class PosTextTile extends StatefulWidget {
  /// The line the operator actually reads. Given two lines before it
  /// ellipsizes, because real category and dish names here run long
  /// ("Salatlar va sovuq zakuskalar").
  final String title;

  /// Colour bar down the leading edge — a category's `colorCode`, or the brand
  /// accent when the row has no colour of its own.
  final Color accent;

  /// Optional glyph between the bar and the title, for the "All categories"
  /// row. Kept small on purpose: it is decoration, not the content.
  final Widget? leading;

  /// Trailing content on the same line as the title — the price, on a meal.
  ///
  /// Taken as text rather than a widget so this class sizes it, like the
  /// title: a caller styling its own price is how the two grids drift apart
  /// again.
  final String? trailingText;

  /// Overlaid at the top-right rather than laid out in the row, so a cart
  /// quantity appearing cannot reflow the name mid-service.
  final Widget? badge;

  final VoidCallback onTap;

  const PosTextTile({
    super.key,
    required this.title,
    required this.accent,
    required this.onTap,
    this.leading,
    this.trailingText,
    this.badge,
  });

  @override
  State<PosTextTile> createState() => _PosTextTileState();
}

class _PosTextTileState extends State<PosTextTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          // So the accent bar can be a plain rectangle: the clip gives it the
          // tile's own left corners, which is one radius to keep in step
          // instead of two.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.bgDefault,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? c.textBrand.withOpacity(0.4) : c.border,
              width: _hovered ? 1.2 : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: c.textBrand.withOpacity(0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              // Type scales with the tile rather than being pinned to a number
              // chosen for one height. This tile was 56px an hour ago and is
              // 84px now; type that does not follow leaves either a cramped row
              // or an ocean of padding around small text. Clamped at both ends
              // so a narrow pane stays legible and a wide screen does not turn
              // a dish name into a headline.
              final title = (box.maxHeight * 0.22).clamp(15.0, 24.0);
              // The price reads a shade smaller than the name — it is the
              // second thing the eye should land on, not the first.
              final price = title - 1;
              final gap = (box.maxHeight * 0.14).clamp(8.0, 16.0);

              return Stack(
                children: [
                  Row(
                    children: [
                      Container(width: 6, color: widget.accent),
                      SizedBox(width: gap),
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: title,
                              fontWeight: FontWeight.w600,
                              color: c.textDefault,
                              fontFamily: PosTypography.family,
                              height: 1.2,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ),
                      if (widget.trailingText != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          widget.trailingText!,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: price,
                            fontWeight: FontWeight.w700,
                            color: c.textDefault,
                            fontFamily: PosTypography.family,
                          ),
                        ),
                      ],
                      SizedBox(width: gap),
                    ],
                  ),
                  if (widget.badge != null)
                    Positioned(top: 6, right: 6, child: widget.badge!),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
