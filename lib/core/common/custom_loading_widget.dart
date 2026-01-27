import 'dart:io';
import 'package:mary_ai_pos/core/extension/for_context.dart';
import 'package:mary_ai_pos/core/utils/size_config.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Platform.isAndroid
          ? CircularProgressIndicator(
              color: color ?? context.colors.bgBrand,
              strokeWidth: wi(2.5),
              backgroundColor: context.colors.bgBrand.withOpacity(.1),
            )
          : CupertinoActivityIndicator(
              color: color ?? context.colors.textDefault,
            ),
    );
  }
}
