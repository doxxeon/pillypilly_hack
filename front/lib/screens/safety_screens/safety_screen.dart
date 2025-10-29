import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import 'match.dart';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({Key? key}) : super(key: key);

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  final List<Map<String, dynamic>> _safetyOptions = [
    {'label': '병용금기', 'icon': Icons.warning, 'color': Colors.redAccent},
    {'label': '노인금기', 'icon': Icons.elderly, 'color': Colors.orangeAccent},
    {'label': '임부금기', 'icon': Icons.pregnant_woman, 'color': Colors.pinkAccent},
    {'label': '특정연령금기', 'icon': Icons.child_care, 'color': Colors.teal},
    {'label': '용량금기', 'icon': Icons.scale, 'color': Colors.indigoAccent},
    {'label': '투여기간금기', 'icon': Icons.timer, 'color': Colors.green},
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final theme = context.read<ThemeService>();
      _speakIntro(theme);
    });
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ko-KR");
    await _flutterTts.setSpeechRate(0.47);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speakIntro(ThemeService theme) async {
    if (theme.isVoiceGuideEnabled) {
      await _flutterTts.speak(
        "약물 안전성 검사 화면입니다. "
        "병용 금기, 노인 금기, 임부 금기 등 중에서 원하시는 항목을 선택해주세요.",
      );
    }
  }

  Future<void> _speakOption(String label, ThemeService theme) async {
    if (!theme.isVoiceGuideEnabled) return;
    
    String message;
    switch (label) {
      case '병용금기':
        message = "병용 금기 약물 간의 상호작용을 확인합니다.";
        break;
      case '노인금기':
        message = "노인에게 사용이 권장되지 않는 약물을 확인합니다.";
        break;
      case '임부금기':
        message = "임신 중 복용이 금지된 약물을 확인합니다.";
        break;
      case '특정연령금기':
        message = "특정 연령대에서 금지된 약물을 확인합니다.";
        break;
      case '용량금기':
        message = "용량 초과 시 위험한 약물을 확인합니다.";
        break;
      case '투여기간금기':
        message = "투여 기간이 제한된 약물을 확인합니다.";
        break;
      default:
        message = "선택한 항목을 확인합니다.";
    }
    await _flutterTts.speak(message);
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '약물 안전성 검사',
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _safetyOptions.map((option) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: AccessibleButton(
                      label: option['label'],
                      icon: option['icon'],
                      hint: '${option['label']} 확인 기능을 실행합니다',
                      width: double.infinity,
                      height: 70,
                      onPressed: () async {
                        await _speakOption(option['label'], theme);
                        await Future.delayed(const Duration(seconds: 1)); // 음성 출력 후 약간의 딜레이
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  MatchVoiceScreen(type: option['label']),
                            ),
                          );
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}