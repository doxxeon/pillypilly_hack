import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static const chatUser = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static const chatBot = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 16,
  );

  static const input = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
  );
}