import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Standard network image with a shimmer placeholder.
///
/// Images are decoded at the size they are displayed, not their source size
/// (the API serves 1600x1200 photos, ~7.7 MB each once decoded).
class TheNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const TheNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: LayoutBuilder(builder: (context, constraints) {
        final boxWidth =
            _finiteOrNull(width) ?? _finiteOrNull(constraints.maxWidth);
        final boxHeight =
            _finiteOrNull(height) ?? _finiteOrNull(constraints.maxHeight);
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);

        // Only one dimension is passed so the decoded image keeps its aspect
        // ratio (passing both would stretch it). For BoxFit.cover with the
        // landscape photos the API serves, a wide box is filled by matching
        // its width and a square/tall box by matching its height.
        int? decodeWidth;
        int? decodeHeight;
        if (boxWidth != null && (boxHeight == null || boxWidth > boxHeight)) {
          decodeWidth = (boxWidth * pixelRatio).round();
        } else if (boxHeight != null) {
          decodeHeight = (boxHeight * pixelRatio).round();
        }

        return CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: decodeWidth,
          memCacheHeight: decodeHeight,
          placeholder: (context, _) => Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(width: width, height: height, color: Colors.white),
          ),
          errorWidget: (context, _, __) => Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            child: const Icon(Icons.image_not_supported_outlined),
          ),
        );
      }),
    );
  }

  static double? _finiteOrNull(double? value) =>
      value != null && value.isFinite ? value : null;
}
