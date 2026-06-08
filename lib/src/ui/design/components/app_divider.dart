import 'package:flutter/material.dart';

import '../tokens.dart';

/// Thin horizontal divider, color from tokens.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppColors.divider,
      indent: indent,
      endIndent: endIndent,
    );
  }
}
