import 'package:flutter/material.dart';
import 'package:pillypilly_h/services/settings_service.dart';

/// 전역 UI/접근성 상태를 관리하는 ChangeNotifier
class ThemeService extends ChangeNotifier {
  // ====== 접근성 상태 ======
  bool _isVoiceGuideEnabled = true; // 음성 안내
  double _fontScale = 1.0;          // 글자 배율 (옵션)
  bool _isHighContrast = false;     // 고대비 (옵션)

  // ====== 공개 getter ======
  bool get isVoiceGuideEnabled => _isVoiceGuideEnabled;
  double get fontScale => _fontScale;
  bool get isHighContrastEnabled => _isHighContrast;
  

  // ====== 앱 시작 시 저장값 로드 ======
  Future<void> loadSettings() async {
    _isVoiceGuideEnabled = await SettingsService.isVoiceGuideEnabled();
    _fontScale = await SettingsService.getFontScale();
    _isHighContrast = await SettingsService.isHighContrastEnabled();
    notifyListeners();
  }

  // ====== 음성 안내 토글 ======
  Future<void> toggleVoiceGuide(bool enabled) async {
    _isVoiceGuideEnabled = enabled;
    await SettingsService.setVoiceGuideEnabled(enabled);
    notifyListeners();
  }

  // ====== (선택) 글자 배율/고대비도 함께 관리 가능 ======
  Future<void> updateFontScale(double scale) async {
    _fontScale = scale.clamp(0.8, 2.0);
    await SettingsService.setFontScale(_fontScale);
    notifyListeners();
  }

  Future<void> updateHighContrast(bool enabled) async {
    _isHighContrast = enabled;
    await SettingsService.setHighContrastEnabled(enabled);
    notifyListeners();
  }

  // ====== (옵션) 색/텍스트 스타일 – 간단 기본값 제공 ======
  // 시인성 높은 쨍한 오렌지 계열(주황)
  Color get primaryColor => const Color(0xFFFF6A00);
  Color get backgroundColor => isHighContrastEnabled ? Colors.black : const Color(0xFFF8F8F8);
  Color get textColor => isHighContrastEnabled ? Colors.white : const Color(0xFF111111);
  Color get buttonColor => primaryColor;
  Color get buttonTextColor => isHighContrastEnabled ? Colors.black : Colors.white;

  TextStyle get titleStyle =>
      TextStyle(fontSize: 22 * fontScale, fontWeight: FontWeight.w700, color: textColor);

  TextStyle get bodyTextStyle =>
      TextStyle(fontSize: 16 * fontScale, fontWeight: FontWeight.w500, color: textColor);

  TextStyle get subtitleTextStyle =>
      TextStyle(fontSize: 14 * fontScale, fontWeight: FontWeight.w400, color: textColor.withOpacity(0.7));

  TextStyle get appBarTitleStyle =>
      TextStyle(fontSize: 20 * fontScale, fontWeight: FontWeight.w700, color: Colors.white);

  TextStyle get buttonTextStyle =>
      TextStyle(fontSize: 18 * fontScale, fontWeight: FontWeight.w700, color: buttonTextColor);
}