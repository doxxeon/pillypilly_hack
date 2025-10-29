import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import 'voice.dart';        // 🎙️ 음성검색 페이지
import 'text.dart';         // ⌨️ 텍스트검색 페이지
import 'camera.dart';       // 📷 카메라검색 페이지

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final FlutterTts tts = FlutterTts();

  Future<void> _navigateTo(String option, ThemeService theme) async {
    Widget page;

    if (theme.isVoiceGuideEnabled) {
      await tts.setLanguage("ko-KR");
      await tts.setSpeechRate(0.45);
    }

    switch (option) {
      case '음성으로 검색하기':
        if (theme.isVoiceGuideEnabled) await tts.speak("음성 검색 화면으로 이동합니다.");
        page = const VoiceSearchScreen();
        break;

      case '텍스트로 검색하기':
        if (theme.isVoiceGuideEnabled) await tts.speak("텍스트 검색 화면으로 이동합니다.");
        page = const TextSearchScreen();
        break;

      case '카메라로 촬영하기':
        if (theme.isVoiceGuideEnabled) await tts.speak("카메라 촬영 화면으로 이동합니다.");
        page = const PillCameraScreen();
        break;

      default:
        page = const Scaffold(
          body: Center(child: Text('페이지를 찾을 수 없습니다.')),
        );
    }

    // ✅ 음성 안내를 사용 중이면 약간의 딜레이로 자연스럽게 이동
    if (theme.isVoiceGuideEnabled) {
      await Future.delayed(const Duration(milliseconds: 700));
    }

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '알약 검색하기',
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccessibleButton(
                  label: '음성으로 검색하기',
                  icon: Icons.mic,
                  hint: '누르면 음성으로 약을 검색할 수 있는 화면으로 이동합니다.',
                  onPressed: () => _navigateTo('음성으로 검색하기', theme),
                ),
                const SizedBox(height: 24),
                AccessibleButton(
                  label: '텍스트로 검색하기',
                  icon: Icons.keyboard,
                  hint: '누르면 직접 입력해서 약을 검색할 수 있는 화면으로 이동합니다.',
                  onPressed: () => _navigateTo('텍스트로 검색하기', theme),
                ),
                const SizedBox(height: 24),
                AccessibleButton(
                  label: '카메라로 촬영하기',
                  icon: Icons.photo_camera,
                  hint: '누르면 카메라를 사용해 알약을 촬영할 수 있는 화면으로 이동합니다.',
                  onPressed: () => _navigateTo('카메라로 촬영하기', theme),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}