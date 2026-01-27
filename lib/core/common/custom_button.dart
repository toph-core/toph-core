import 'package:mary_ai_pos/core/common/custom_loading_widget.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/utils/size_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:scale_button/scale_button.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.text,
    required this.onTap,
    this.radius,
    this.bgColor,
    this.textColor,
    this.isLoading = false,
    this.paddingV,
    this.fontSize,
    this.colorL,
    this.icon,
    this.rightW,
    this.borderColor,
    this.mainAxisAlignment,
    this.fontWeight,
    this.height,
    this.iconColor,
    this.paddingH,
    this.isActive = true,
    this.textStyle,
  });

  final String text;
  final Function()? onTap;
  final BorderRadius? radius;
  final double? paddingV;
  final double? paddingH;
  final double? fontSize;
  final Color? colorL;
  final String? icon;
  final Color? bgColor;
  final Color? borderColor;
  final Color? textColor;
  final Color? iconColor;
  final bool isLoading;
  final bool isActive;

  final double? height;
  final Widget? rightW;
  final MainAxisAlignment? mainAxisAlignment;
  final FontWeight? fontWeight;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return ScaleButton(
      bound: 0.030,
      onTap: isActive ? onTap : null,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius ?? context.radius.buttonLg,
        child: InkWell(
          splashColor: context.colors.textDefault.withOpacity(.2),
          highlightColor: Colors.transparent,
          borderRadius: radius ?? context.radius.buttonLg,
          onTap: isActive ? onTap : null,
          child: Ink(
            height: he(height ?? 50),
            padding: EdgeInsets.symmetric(
              vertical: isLoading ? he(8) : he(paddingV ?? 12),
              horizontal: wi(paddingH ?? 8),
            ),
            decoration: BoxDecoration(
              borderRadius: radius ?? context.radius.buttonLg,
              border: Border.all(
                color: borderColor ?? context.colors.border,
                width: 1,
              ),
              color: isActive
                  ? (bgColor ?? context.colors.buttonBrand)
                  : context.colors.bgSecondary,
            ),
            child: Row(
              mainAxisAlignment: mainAxisAlignment ?? MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                isLoading
                    ? SizedBox(
                        height: he(29),
                        width: he(29),
                        child: Center(
                          child: LoadingWidget(
                            color: colorL ?? context.colors.iconOnBrand,
                          ),
                        ),
                      )
                    : Center(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            icon != null
                                ? SvgPicture.asset(
                                    icon ?? "",
                                    colorFilter: iconColor == null
                                        ? null
                                        : ColorFilter.mode(
                                            iconColor!,
                                            BlendMode.srcIn,
                                          ),
                                  ).paddingOnly(right: wi(8), left: wi(8))
                                : const SizedBox.shrink(),
                            Text(
                              text,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  textStyle ??
                                  context.textStyles.bodyMd.copyWith(
                                    color: isActive
                                        ? (textColor ??
                                              context.colors.textOnBrand)
                                        : context.colors.textTertiary,
                                    fontSize: fontSize,
                                    fontWeight: fontWeight ?? FontWeight.w500,
                                  ),
                            ),
                            rightW ?? const SizedBox.shrink(),
                          ],
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomOutlineButton extends StatelessWidget {
  const CustomOutlineButton({
    super.key,
    required this.text,
    required this.onTap,
    this.primaryColor,
    this.textColor,
    this.radius,
    this.isLoading = false,
    this.mainAxisAlignment,
    this.bgColor,
    this.leftW,
    this.colorL,
    this.rightW,
    this.fontSize,
    this.fontWeight,
    this.paddingH,
    this.paddingV,
    this.height,
  });

  final String text;
  final Function() onTap;
  final Color? textColor;
  final Color? primaryColor;
  final Color? bgColor;
  final Color? colorL;
  final double? radius;
  final bool isLoading;
  final Widget? leftW;
  final Widget? rightW;
  final MainAxisAlignment? mainAxisAlignment;
  final FontWeight? fontWeight;
  final double? fontSize;
  final double? paddingV;
  final double? paddingH;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ScaleButton(
      bound: 0.030,
      onTap: onTap,
      child: Material(
        borderRadius: BorderRadius.circular(radius ?? 12),
        child: InkWell(
          splashColor: context.colors.textBrand.withOpacity(.1),
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(radius ?? 12),
          onTap: onTap,
          child: Ink(
            height: he(height ?? 50),
            padding: EdgeInsets.symmetric(
              vertical: isLoading ? he(8) : he(paddingV ?? 12),
              horizontal: wi(paddingH ?? 8),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius ?? 12),
              border: Border.all(
                color: primaryColor ?? context.colors.borderBrand,
                width: wi(1.5),
              ),
              color: bgColor ?? context.colors.textDefault,
            ),
            child: Row(
              mainAxisAlignment: mainAxisAlignment ?? MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment:
                      mainAxisAlignment ?? MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    isLoading
                        ? SizedBox(
                            height: he(29),
                            width: he(29),
                            child: Center(child: LoadingWidget(color: colorL)),
                          )
                        : Center(
                            child: Row(
                              children: [
                                leftW?.paddingOnly(right: wi(16)) ??
                                    const SizedBox.shrink(),
                                Text(
                                  text,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textStyles.bodyMd.copyWith(
                                    color:
                                        textColor ?? context.colors.textDefault,
                                    fontWeight: fontWeight,
                                    fontSize: fontSize ?? he(16),
                                  ),
                                ),
                                rightW ?? const SizedBox.shrink(),
                              ],
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomIconButton extends StatelessWidget {
  const CustomIconButton({
    super.key,
    this.onTap,
    this.radius,
    this.bgColor,
    this.paddingV,
    this.paddingH,
    this.icon,
    this.rightW,
    this.height,
    this.borderColor,
    this.iconcolor,
    this.heightIcon,
    this.borderWidth,
  });

  final Function()? onTap;
  final double? radius;
  final double? paddingV;
  final double? paddingH;
  final double? height;
  final String? icon;
  final Color? bgColor;
  final Color? borderColor;
  final Color? iconcolor;
  final Widget? rightW;
  final double? heightIcon;
  final double? borderWidth;

  @override
  Widget build(BuildContext context) {
    return ScaleButton(
      onTap: onTap,
      bound: 0.030,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: he(height ?? 45),
        width: he(height ?? 45),
        padding: EdgeInsets.symmetric(
          vertical: he(paddingV ?? 12),
          horizontal: wi(paddingH ?? 8),
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: borderColor ?? context.colors.textBrand,
            width: borderWidth ?? 1.0,
          ),
          borderRadius: BorderRadius.circular(radius ?? 12),
          color: bgColor ?? context.colors.buttonBrand,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null)
              Center(
                child: SvgPicture.asset(
                  icon!,
                  color: iconcolor,
                  height: heightIcon,
                  fit: BoxFit.cover,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
