import 'package:flutter/material.dart';
import 'settings_service.dart';

class ThemeService extends ChangeNotifier {
  static ThemeService? _instance;
  static ThemeService get instance => _instance ??= ThemeService._();
  
  ThemeService._() {
    _loadSettings();
  }

  bool _isVoiceGuideEnabled = true;
  bool _isHighContrastEnabled = false;
  double _fontScale = 1.0;

  // ✅ 기존 getter 유지
  bool get isVoiceGuideEnabled => _isVoiceGuideEnabled;
  bool get isHighContrastEnabled => _isHighContrastEnabled;
  double get fontScale => _fontScale;

  // ✅ BoxScreen 등에서 쓰는 단축 alias 추가
  bool get isHighContrast => _isHighContrastEnabled;

  // ===============================
  // 🎨 색상 테마
  // ===============================
  Color get primaryColor => _isHighContrastEnabled ? Colors.amber[700]! : Colors.amber[700]!;
  Color get backgroundColor => _isHighContrastEnabled ? Colors.black : Colors.white;
  Color get textColor => _isHighContrastEnabled ? Colors.yellowAccent : Colors.black;
  Color get buttonColor => _isHighContrastEnabled ? Colors.amber[700]! : Colors.amber[700]!;
  Color get buttonTextColor => _isHighContrastEnabled ? Colors.black : Colors.black;

  // ===============================
  // 🔤 텍스트 스타일
  // ===============================
  TextStyle get titleStyle => TextStyle(
    fontSize: 26 * _fontScale,
    fontWeight: FontWeight.bold,
    color: textColor,
  );

  TextStyle get appBarTitleStyle => TextStyle(
    fontSize: 22 * _fontScale,
    fontWeight: FontWeight.bold,
    color: textColor,
  );

  TextStyle get buttonTextStyle => TextStyle(
    fontSize: 20 * _fontScale,
    fontWeight: FontWeight.bold,
    color: buttonTextColor,
  );

  TextStyle get bodyTextStyle => TextStyle(
    fontSize: 16 * _fontScale,
    color: textColor,
  );

  TextStyle get subtitleTextStyle => TextStyle(
    fontSize: 14 * _fontScale,
    color: textColor.withOpacity(0.7),
  );

  // ===============================
  // ⚙️ 설정 로드 및 업데이트
  // ===============================
  Future<void> _loadSettings() async {
    _isVoiceGuideEnabled = await SettingsService.isVoiceGuideEnabled();
    _isHighContrastEnabled = await SettingsService.isHighContrastEnabled();
    _fontScale = await SettingsService.getFontScale();
    notifyListeners();
  }

  Future<void> updateVoiceGuide(bool enabled) async {
    _isVoiceGuideEnabled = enabled;
    await SettingsService.setVoiceGuideEnabled(enabled);
    notifyListeners();
  }

  Future<void> updateHighContrast(bool enabled) async {
    _isHighContrastEnabled = enabled;
    await SettingsService.setHighContrastEnabled(enabled);
    notifyListeners();
  }

  Future<void> updateFontScale(double scale) async {
    _fontScale = scale;
    await SettingsService.setFontScale(scale);
    notifyListeners();
  }

  Future<void> refreshSettings() async {
    await _loadSettings();
  }
}

// ===============================
// 🎨 AppColors (ThemeService와 호환)
// ===============================
class AppColors {
  static Color background(BuildContext context) =>
      ThemeService.instance.backgroundColor;
  static Color primary(BuildContext context) =>
      ThemeService.instance.primaryColor;
  static Color accent(BuildContext context) =>
      ThemeService.instance.buttonColor;
  static Color confirm(BuildContext context) =>
      ThemeService.instance.primaryColor;
  static Color error(BuildContext context) => Colors.red[700]!;
  static Color errorLight(BuildContext context) => Colors.red[50]!;
  static Color textPrimary(BuildContext context) =>
      ThemeService.instance.textColor;
  static Color card(BuildContext context) =>
      ThemeService.instance.backgroundColor.withOpacity(0.95);
}

// ===============================
// 🔤 AppTextStyles (동적 폰트배율 반영)
// ===============================
class AppTextStyles {
  static TextStyle largeButton(BuildContext context) =>
      ThemeService.instance.buttonTextStyle;

  static TextStyle title(BuildContext context) =>
      ThemeService.instance.titleStyle;

  static TextStyle body(BuildContext context) =>
      ThemeService.instance.bodyTextStyle;
}