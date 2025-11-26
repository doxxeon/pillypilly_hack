import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final FlutterTts _tts = FlutterTts();
  static bool _inited = false;

  TTSService() {
    if (!_inited) {
      _init();
      _inited = true;
    }
  }

  Future<void> _init() async {
    try {
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.52); // 0.0 ~ 1.0
      await _tts.setPitch(1.0);       // 0.5 ~ 2.0
      await _tts.setVolume(1.0);      // 0.0 ~ 1.0
    } catch (_) {
      // 플러그인 미설치/플랫폼 미지원 시 조용히 무시
    }
  }

  /// main_screen에서 호출하는 메서드
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}