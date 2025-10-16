import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _ttsKey = 'voice_guide_enabled';
  static const _fontSizeKey = 'font_size_scale';
  static const _contrastKey = 'high_contrast_enabled';

  /// ✅ 음성 안내 여부
  static Future<bool> isVoiceGuideEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ttsKey) ?? true;
  }

  static Future<void> setVoiceGuideEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ttsKey, enabled);
  }

  /// ✅ 글자 크기 배율 (1.0 = 기본)
  static Future<double> getFontScale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_fontSizeKey) ?? 1.0;
  }

  static Future<void> setFontScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, scale);
  }

  /// ✅ 고대비 모드
  static Future<bool> isHighContrastEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_contrastKey) ?? false;
  }

  static Future<void> setHighContrastEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_contrastKey, enabled);
  }
}