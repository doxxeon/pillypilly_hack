import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart'; // ✅ 음성 안내용
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

  Future<void> _navigateTo(String option) async {
    Widget page;

    // 기본 음성 설정
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);

    switch (option) {
      case '음성으로 검색하기':
        await tts.speak("음성 검색 화면으로 이동합니다.");
        page = const VoiceSearchScreen();
        break;
      case '텍스트로 검색하기':
        await tts.speak("텍스트 검색 화면으로 이동합니다.");
        page = const TextSearchScreen();
        break;
      case '카메라로 촬영하기':
        await tts.speak("카메라 촬영 화면으로 이동합니다.");
        page = const PillCameraScreen();
        break;
      default:
        page = const Scaffold(
          body: Center(child: Text('페이지를 찾을 수 없습니다.')),
        );
    }

    // 약간의 딜레이를 줘서 TTS 음성이 자연스럽게 나오고 나서 이동
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: '알약 검색하기',
          child: const Text('알약 검색하기'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label: '음성으로 검색하기 버튼',
              hint: '누르면 음성으로 약을 검색할 수 있는 화면으로 이동합니다.',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.mic, size: 32),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text('음성으로 검색하기', style: TextStyle(fontSize: 20)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(70),
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _navigateTo('음성으로 검색하기'),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              button: true,
              label: '텍스트로 검색하기 버튼',
              hint: '누르면 직접 입력해서 약을 검색할 수 있는 화면으로 이동합니다.',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.keyboard, size: 32),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text('텍스트로 검색하기', style: TextStyle(fontSize: 20)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(70),
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _navigateTo('텍스트로 검색하기'),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              button: true,
              label: '카메라로 촬영하기 버튼',
              hint: '누르면 카메라를 사용해 알약을 촬영할 수 있는 화면으로 이동합니다.',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.photo_camera, size: 32),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text('카메라로 촬영하기', style: TextStyle(fontSize: 20)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(70),
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _navigateTo('카메라로 촬영하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}