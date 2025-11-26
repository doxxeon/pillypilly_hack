import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pillypilly_h/services/theme_service.dart';

class AppTextStyles {
  static TextStyle title(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).titleStyle;

  static TextStyle subtitle(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).subtitleTextStyle;

  static TextStyle body(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).bodyTextStyle;

  static TextStyle largeButton(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).buttonTextStyle;

  // 챗봇 등에서 사용하던 이름 유지
  static TextStyle get chatUser => const TextStyle(fontWeight: FontWeight.w700);
  static TextStyle get chatBot => const TextStyle(fontWeight: FontWeight.w500);
  static TextStyle get input => const TextStyle(fontSize: 16);
}