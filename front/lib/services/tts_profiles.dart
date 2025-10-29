import 'package:flutter_tts/flutter_tts.dart';

class TTSProfiles {
  final FlutterTts tts;

  TTSProfiles(this.tts);

  // 🔊 공통 speak 함수 추가
  Future<void> speak(String text) async {
    await tts.stop(); // 중복 발화 방지
    await tts.speak(text);
  }

  /// 🌸 부드러운 여성 음성
  Future<void> softFemale() async {
    await tts.setLanguage("ko-KR");
    await tts.setPitch(1.1);
    await tts.setSpeechRate(0.45);
    await tts.setVoice({"name": "ko-kr-x-kob-local", "locale": "ko-KR"});
  }

  /// 💬 차분한 남성 음성
  Future<void> deepMale() async {
    await tts.setLanguage("ko-KR");
    await tts.setPitch(0.8);
    await tts.setSpeechRate(0.4);
    await tts.setVoice({"name": "ko-kr-x-kod-local", "locale": "ko-KR"});
  }

  /// 🤖 AI 어시스턴트 톤
  Future<void> assistantTone() async {
    await tts.setLanguage("ko-KR");
    await tts.setPitch(1.0);
    await tts.setSpeechRate(0.5);
    await tts.setVoice({"name": "ko-kr-x-kof-local", "locale": "ko-KR"});
  }

  /// 🧠 기계적 음성
  Future<void> robotic() async {
    await tts.setLanguage("ko-KR");
    await tts.setPitch(1.3);
    await tts.setSpeechRate(0.6);
    await tts.setVoice({"name": "ko-kr-x-koc-local", "locale": "ko-KR"});
  }
}