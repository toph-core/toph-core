import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mary_ai_pos/core/media/local_image_cache.dart';
import 'package:mary_ai_pos/core/common/custom_shimmer_container.dart';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/extension/widget_extension.dart';
import 'package:mary_ai_pos/core/values/app_assets.dart';
import 'package:mary_ai_pos/di.dart';
import 'package:mary_ai_pos/features/view/main/domain/repository/menu_repository.dart';

class CustomCachedNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final String? minioObjectName;
  final double height;
  final double width;
  final double iconSize;
  final String? title;
  final bool border;
  final BoxFit? fit;
  final String? errorIcon;
  final BorderRadius? borderRadius;
  final Widget? errorWidget;

  const CustomCachedNetworkImage({
    super.key,
    this.imageUrl,
    this.minioObjectName,
    required this.height,
    required this.width,
    this.border = false,
    this.iconSize = 60,
    this.title,
    this.fit,
    this.errorIcon,
    this.borderRadius,
    this.errorWidget,
  }) : assert(
         imageUrl != null || minioObjectName != null,
         "Either imageUrl or minioObjectName must be provided",
       );

  @override
  Widget build(BuildContext context) {
    if (minioObjectName != null) {
      // Was a FutureBuilder straight onto MinioService, which meant a fetch per
      // build and nothing kept: `MinioService` memoizes only per process, so
      // these images were re-downloaded every app start and simply did not
      // exist offline. The repository serves them from disk and fetches once on
      // a miss — same pixels, one request, and they survive a restart.
      return StreamBuilder<LocalImage>(
        stream: inject<MenuRepository>().imageStream(minioObjectName!),
        builder: (context, snapshot) {
          final image = snapshot.data;
          if (image == null || image.status == ImageStatus.loading) {
            return _placeholder();
          }
          final bytes = image.bytes;
          if (image.status == ImageStatus.missing ||
              bytes == null ||
              bytes.isEmpty) {
            return _resolveErrorWidget(context);
          }
          return ClipRRect(
            borderRadius: borderRadius ?? BorderRadius.zero,
            child: Image.memory(
              Uint8List.fromList(bytes),
              height: height,
              width: width,
              fit: fit ?? BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) =>
                  _resolveErrorWidget(context),
            ),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        height: height,
        width: width,
        fit: fit ?? BoxFit.cover,
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _resolveErrorWidget(context),
      ),
    );
  }

  Widget _resolveErrorWidget(BuildContext context) =>
      errorWidget ?? _errorWidget(context);

  Widget _placeholder() =>
      CustomShimmerBox(h: height, w: width, borderRadius: borderRadius);

  Widget _errorWidget(BuildContext context) => Container(
    height: height,
    width: width,
    decoration: BoxDecoration(
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      color: context.colors.bgDefault,
      border: border ? Border.all(color: context.colors.border) : null,
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          errorIcon ?? AppIcons.icNoImage,
          height: iconSize,
          fit: BoxFit.contain,
          color: context.colors.iconSecondary,
        ),
        if (title != null)
          Text(
            title!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ).paddingOnly(top: 8),
      ],
    ),
  );
}
