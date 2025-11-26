import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pillypilly_h/services/theme_service.dart';

class AppColors {
  static Color primary(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).primaryColor;

  static Color background(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).backgroundColor;

  static Color textPrimary(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).textColor;

  static Color accent(BuildContext ctx) => primary(ctx);

  static Color card(BuildContext ctx) =>
      Provider.of<ThemeService>(ctx, listen: false).isHighContrastEnabled
          ? Colors.white
          : Colors.white;

  static Color error(BuildContext ctx) => Colors.red.shade600;
  static Color errorLight(BuildContext ctx) => Colors.red.shade100;

  static Color confirm(BuildContext ctx) => Colors.green.shade600;
}