import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class AccessibleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final String? hint;
  final double? width;
  final double? height;
  final EdgeInsets? padding;

  // ✅ 추가된 속성들
  final Color? backgroundColor;
  final TextStyle? textStyle;

  const AccessibleButton({
    Key? key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.hint,
    this.width,
    this.height,
    this.padding,
    this.backgroundColor, // ✅ 추가됨
    this.textStyle,       // ✅ 추가됨
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        final bgColor = backgroundColor ?? theme.buttonColor;
        final txtStyle = textStyle ?? theme.buttonTextStyle;

        return Semantics(
          button: true,
          label: label,
          hint: hint,
          child: SizedBox(
            width: width,
            height: height ?? 80,
            child: ElevatedButton.icon(
              icon: Icon(icon, size: 32, color: theme.buttonTextColor),
              label: Padding(
                padding: padding ?? const EdgeInsets.symmetric(vertical: 24.0),
                child: Text(label, style: txtStyle),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: bgColor, // ✅ 외부에서 받은 색 우선
                foregroundColor: theme.buttonTextColor,
                minimumSize: Size.fromHeight(height ?? 80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
              ),
              onPressed: onPressed,
            ),
          ),
        );
      },
    );
  }
}