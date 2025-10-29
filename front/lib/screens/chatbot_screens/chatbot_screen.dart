import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart'; // 진동용
import '../../widgets/accessible_scaffold.dart';
import '../../services/theme_service.dart';
import '../../utils/app_colors.dart' as u;

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _recognizedText = "";

  @override
  void initState() {
    super.initState();
    _initTTS();
    _welcome();
  }

  Future<void> _initTTS() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setPitch(1.0);
  }

  Future<void> _welcome() async {
    await _tts.speak("필리 챗봇에 오신 걸 환영합니다. 중앙의 마이크 버튼을 누르고 말씀해주세요.");
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      await _tts.speak("음성 입력이 종료되었습니다.");
    } else {
      bool available = await _speech.initialize();
      if (available) {
        setState(() {
          _isListening = true;
          _recognizedText = "";
        });

        // 진동으로 피드백
        HapticFeedback.mediumImpact();
        await _tts.speak("지금부터 말씀해주세요.");

        _speech.listen(
          localeId: "ko_KR",
          onResult: (result) async {
            setState(() => _recognizedText = result.recognizedWords);
            if (result.finalResult) {
              setState(() => _isListening = false);
              await _handleResponse(result.recognizedWords);
            }
          },
        );
      } else {
        await _tts.speak("음성 인식 기능을 사용할 수 없습니다.");
      }
    }
  }

  Future<void> _handleResponse(String input) async {
    if (input.isEmpty) return;
    await _tts.speak("말씀하신 내용은 $input 입니다.");
    await Future.delayed(const Duration(seconds: 1));
    await _tts.speak("이 약은 하루에 두 번 복용하시면 됩니다.");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeService>(context);

    return AccessibleScaffold(
      title: "필리챗봇 💊",
      backgroundColor:
          theme.isHighContrast ? Colors.black : u.AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 안내 문구
            Text(
              _isListening ? "말씀을 인식 중입니다..." : "마이크 버튼을 눌러 말씀해주세요",
              style: TextStyle(
                fontSize: 18,
                color: theme.isHighContrast ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 40),
            // 마이크 버튼
            GestureDetector(
              onTap: _toggleListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isListening ? 140 : 120,
                height: _isListening ? 140 : 120,
                decoration: BoxDecoration(
                  color: _isListening
                      ? u.AppColors.accent.withOpacity(0.9)
                      : Colors.grey[400],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: _isListening ? 16 : 8,
                      spreadRadius: _isListening ? 4 : 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 40),
            // 인식된 음성 텍스트
            if (_recognizedText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "“$_recognizedText”",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: theme.isHighContrast
                        ? Colors.white70
                        : Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}