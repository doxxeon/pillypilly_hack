import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vibration/vibration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '/api_services/api_helper.dart';
import '/api_services/token_service.dart';

class AgeContraScreen extends StatefulWidget {
  const AgeContraScreen({Key? key}) : super(key: key);

  @override
  State<AgeContraScreen> createState() => _AgeContraScreenState();
}

class _AgeContraScreenState extends State<AgeContraScreen> {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _isListening = false;
  bool _isBusy = false;

  List<Map<String, dynamic>> _options = [];
  Map<String, dynamic>? _selectedDrug;

  @override
  void initState() {
    super.initState();
    _startIntro();
  }

  Future<void> _startIntro() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.47);
    await _tts.setPitch(1.0);
    await _tts.speak("특정 연령 금기 약물 확인 화면입니다. 약 이름을 말씀해주세요.");
    _tts.setCompletionHandler(() async {
      await Vibration.vibrate(duration: 120);
      await Future.delayed(const Duration(milliseconds: 250));
      await _listen();
    });
  }

  Future<void> _listen() async {
    if (_isListening || _isBusy) return;
    setState(() => _isListening = true);

    bool available = await _stt.initialize(
      onStatus: (status) => debugPrint("🎤 STT status: $status"),
      onError: (err) => debugPrint("❌ STT error: $err"),
    );

    if (available) {
      await _stt.listen(
        localeId: "ko_KR",
        onResult: (result) async {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            final input = result.recognizedWords.trim();
            debugPrint("🗣 User said: $input");
            await _handleInput(input);
          }
        },
      );
    } else {
      await _tts.speak("음성 인식을 시작할 수 없습니다.");
    }
  }

  Future<void> _stopListening() async {
    if (_isListening) {
      await _stt.stop();
      setState(() => _isListening = false);
    }
  }

  Future<void> _handleInput(String keyword) async {
    await _stopListening();
    setState(() => _isBusy = true);

    try {
      await _searchDrug(keyword);
    } finally {
      setState(() => _isBusy = false);
    }
  }

  /// 🔍 약 검색
  Future<void> _searchDrug(String keyword) async {
    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = Uri.parse('$baseUrl/keyword-search?keyword=$keyword');
      final headers = await ApiHelper.getAuthHeaders();

      debugPrint("🌐 GET $url");
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = List<Map<String, dynamic>>.from(data['results']?['items'] ?? []);

        if (items.isEmpty) {
          await _tts.speak("검색 결과가 없습니다. 다시 말씀해주세요.");
          _tts.setCompletionHandler(() async => _listen());
          return;
        }

        _options = items;
        final names = items.map((e) => e['itemName']).take(5).join(", ");
        await _tts.speak("$names 등이 있습니다. 이 중 선택하실 약 이름을 말씀해주세요.");
        _tts.setCompletionHandler(() async => _listen());
      } else {
        await _tts.speak("서버에서 데이터를 불러오지 못했습니다. (${response.statusCode})");
      }
    } catch (e) {
      debugPrint("❌ 검색 오류: $e");
      await _tts.speak("검색 중 오류가 발생했습니다. 네트워크 상태를 확인해주세요.");
    }
  }

  /// ✅ 특정연령금기 확인
  Future<void> _checkAgeContra(String input) async {
    final matched = _options.firstWhere(
      (item) => (item['itemName'] as String).contains(input),
      orElse: () => {},
    );

    if (matched.isEmpty) {
      await _tts.speak("해당 이름의 약을 찾지 못했습니다. 다시 말씀해주세요.");
      _tts.setCompletionHandler(() async => _listen());
      return;
    }

    _selectedDrug = matched;
    await Vibration.vibrate(duration: 120);
    await _tts.speak("${matched['itemName']}을 선택하셨습니다. 특정 연령 금기 정보를 불러옵니다.");

    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = Uri.parse('$baseUrl/api/v3/log');
      final headers = await ApiHelper.getAuthHeaders();

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode([matched['itemSeq']]),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = Map<String, dynamic>.from(data['results']);
        await _analyzeAgeData(results);
      } else {
        await _tts.speak("서버 응답이 올바르지 않습니다.");
      }
    } catch (e) {
      debugPrint("❌ 서버 오류: $e");
      await _tts.speak("서버 연결 중 오류가 발생했습니다.");
    }
  }

  /// 📊 특정연령금기 분석
  Future<void> _analyzeAgeData(Map<String, dynamic> results) async {
    bool found = false;
    for (var entry in results.values) {
      final detail = entry['dur']?['ageTaboo'] ?? [];
      if (detail.isNotEmpty) {
        found = true;
        for (var d in detail) {
          final name = d['ITEM_NAME'] ?? '약물명 미상';
          final target = d['AGE_TABOO_CONTENT'] ?? '연령 정보 없음';
          await _tts.speak("$name은 특정 연령 금기 약물입니다. $target");
        }
      }
    }
    if (!found) {
      await _tts.speak("선택하신 약은 특정 연령 금기 항목에 포함되지 않습니다.");
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("특정연령금기 검사"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.blueAccent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.child_care, color: Colors.blueAccent, size: 64),
              const SizedBox(height: 20),
              const Text(
                "특정 연령 금기 약물 검사 화면입니다.\n음성으로 약 이름을 말씀해주세요.",
                style: TextStyle(color: Colors.white70, fontSize: 18, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              if (_isListening)
                const Text("🎙 듣는 중...", style: TextStyle(color: Colors.greenAccent))
              else
                ElevatedButton.icon(
                  onPressed: _listen,
                  icon: const Icon(Icons.mic, color: Colors.black),
                  label: const Text("음성 다시 입력", style: TextStyle(color: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    minimumSize: const Size(200, 48),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}