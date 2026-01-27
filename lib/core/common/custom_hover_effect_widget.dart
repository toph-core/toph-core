import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:flutter/material.dart';

class CustomHoverEffectWidget extends StatelessWidget {
  final Widget child;
  final Color? bgColor;
  final Function() onTap;
  final Color? borderColor;
  final double borderWidth;
  final Color? highlightColor;
  final BorderRadius borderRadius;

  const CustomHoverEffectWidget({
    super.key,
    this.bgColor,
    this.borderColor,
    required this.child,
    required this.onTap,
    this.highlightColor,
    this.borderWidth = 1.0,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor ?? context.colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          width: borderWidth,
          color: borderColor ?? Colors.transparent,
        ),
      ),
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor:
            highlightColor ?? context.colors.bgBrand.withOpacity(.1),
        borderRadius: borderRadius,
        onTap: onTap,
        child: child,
      ),
    );
  }
}
