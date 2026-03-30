import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  final double size;
  final IconData icon;
  final ImageProvider<Object>? image;
  final BoxFit imageFit;
  final Color iconColor;

  const BrandMark({
    super.key,
    this.size = 114,
    this.icon = Icons.account_balance_rounded,
    this.image,
    this.imageFit = BoxFit.contain,
    this.iconColor = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = image != null;
    final width = hasImage ? size * 1.68 : size;
    final height = size;

    return Center(
      child: hasImage
          ? SizedBox(
              width: width,
              height: height,
              child: Image(image: image!, fit: imageFit),
            )
          : Icon(icon, color: iconColor, size: size),
    );
  }
}
