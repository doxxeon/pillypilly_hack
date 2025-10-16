import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vibration/vibration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '/api_services/api_helper.dart';
import '/api_services/token_service.dart';

enum InteractionStep {
  intro,
  firstDrug,
  selectDrug,
  addMore,
  finalConfirm,
  result,
}

class MatchVoiceScreen extends StatefulWidget {
  final String type; // ✅ 추가 (병용금기 등 타입)
  const MatchVoiceScreen({super.key, required this.type});

  @override
  State<MatchVoiceScreen> createState() => _MatchVoiceScreenState();
}

class _MatchVoiceScreenState extends State<MatchVoiceScreen> {
  final FlutterTts tts = FlutterTts();
  final stt.SpeechToText sttInstance = stt.SpeechToText();

  InteractionStep step = InteractionStep.intro;
  bool isListening = false;
  bool isBusy = false;

  String? currentKeyword;
  List<Map<String, dynamic>> currentOptions = [];
  List<Map<String, dynamic>> selectedDrugs = [];

  @override
  void initState() {
    super.initState();
    _startIntro();
  }

  Future<void> _speak(String text, {bool listenAfter = false}) async {
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    await tts.stop();
    await tts.speak(text);

    // ✅ 안내 음성이 끝난 후 자동으로 "지금부터 말씀해주세요" 실행
    tts.setCompletionHandler(() async {
      if (listenAfter && mounted) {
        await tts.speak("지금부터 말씀해주세요.");
        tts.setCompletionHandler(() async {
          await Vibration.vibrate(duration: 120);
          await Future.delayed(const Duration(milliseconds: 250));
          await _listenForSpeech();
        });
      }
    });
  }

  Future<void> _startIntro() async {
    await _speak("${widget.type} 확인 화면입니다. 첫 번째 약의 이름을 말씀해주세요.", listenAfter: true);
    setState(() => step = InteractionStep.firstDrug);
  }

  Future<void> _listenForSpeech() async {
    if (isListening || isBusy) return;
    setState(() => isListening = true);

    bool available = await sttInstance.initialize(
      onStatus: (status) => debugPrint("🎤 STT status: $status"),
      onError: (err) => debugPrint("❌ STT error: $err"),
    );

    if (available) {
      await sttInstance.listen(
        localeId: "ko_KR",
        onResult: (result) async {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            final input = result.recognizedWords.trim();
            debugPrint("🗣 User said: $input");
            await _handleSpeechInput(input);
          }
        },
      );
    } else {
      await _speak("음성 인식을 시작할 수 없습니다.");
    }
  }

  Future<void> _stopListening() async {
    if (isListening) {
      await sttInstance.stop();
      setState(() => isListening = false);
    }
  }

  Future<void> _handleSpeechInput(String input) async {
    await _stopListening();
    setState(() => isBusy = true);

    switch (step) {
      case InteractionStep.firstDrug:
        currentKeyword = input;
        await _searchDrugByKeyword(input);
        break;

      case InteractionStep.selectDrug:
        await _selectDrugFromOptions(input);
        break;

      case InteractionStep.addMore:
        if (input.contains("네")) {
          await _speak("추가할 약의 이름을 말씀해주세요.", listenAfter: true);
          setState(() => step = InteractionStep.firstDrug);
        } else {
          final names = selectedDrugs.map((d) => d['itemName']).join(", ");
          await _speak("현재 선택된 약은 $names 입니다. 병용금기를 확인하시겠습니까?", listenAfter: true);
          setState(() => step = InteractionStep.finalConfirm);
        }
        break;

      case InteractionStep.finalConfirm:
        if (input.contains("네")) {
          await _sendSelectedDrugsToLog();
        } else {
          await _speak("검색을 취소했습니다. 첫 번째 약부터 다시 시작합니다.", listenAfter: true);
          selectedDrugs.clear();
          setState(() => step = InteractionStep.firstDrug);
        }
        break;

      default:
        break;
    }

    setState(() => isBusy = false);
  }

  /// 🔍 약 검색 API 호출
  Future<void> _searchDrugByKeyword(String keyword) async {
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
          await _speak("검색 결과가 없습니다. 다시 말씀해주세요.", listenAfter: true);
          return;
        }

        currentOptions = items;
        final names = items.map((e) => e['itemName']).take(5).join(", ");
        await _speak("$names 등이 있습니다. 이 중 선택하실 약 이름을 말씀해주세요.", listenAfter: true);
        setState(() => step = InteractionStep.selectDrug);
      } else {
        await _speak("서버에서 데이터를 불러오지 못했습니다. (${response.statusCode})", listenAfter: true);
      }
    } catch (e) {
      debugPrint("❌ 검색 오류: $e");
      await _speak("검색 중 오류가 발생했습니다. 네트워크 상태를 확인해주세요.", listenAfter: true);
    }
  }

  /// ✅ 약 선택 처리
  Future<void> _selectDrugFromOptions(String input) async {
    final matched = currentOptions.firstWhere(
      (item) => (item['itemName'] as String).contains(input),
      orElse: () => {},
    );

    if (matched.isEmpty) {
      await _speak("해당 이름의 약을 찾지 못했습니다. 다시 말씀해주세요.", listenAfter: true);
      return;
    }

    selectedDrugs.add(matched);
    await Vibration.vibrate(duration: 120);

    await _speak("${matched['itemName']} 선택되었습니다. 추가로 검색할 약이 있으신가요?", listenAfter: true);
    setState(() => step = InteractionStep.addMore);
  }

  /// 📤 선택 약 리스트를 서버로 전송하여 병용금기 검사
  Future<void> _sendSelectedDrugsToLog() async {
    await Vibration.vibrate(duration: 200);
    await _speak("서버로 정보를 전송합니다.");

    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = Uri.parse('$baseUrl/api/v3/log');
      final headers = await ApiHelper.getAuthHeaders();
      final itemSeqs = selectedDrugs.map((e) => e['itemSeq']).toList();

      debugPrint("📡 POST $url");
      debugPrint("Body: $itemSeqs");

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(itemSeqs),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = Map<String, dynamic>.from(data['results']);
        await _checkCombinations(results);
      } else {
        await _speak("⚠️ 서버 응답이 올바르지 않습니다. (${response.statusCode})");
      }
    } catch (e) {
      await _speak("서버 연결 중 오류가 발생했습니다. 인터넷 상태를 확인해주세요.");
      debugPrint("❌ 서버 오류: $e");
    }

    await Vibration.vibrate(duration: 250);
    setState(() => step = InteractionStep.result);
  }

  /// 🚫 병용금기 검사 로직
  Future<void> _checkCombinations(Map<String, dynamic> results) async {
    bool found = false;
    final entries = results.entries.toList();

    for (int i = 0; i < entries.length; i++) {
      final a = entries[i].value;
      final aName = a['permit']?['permitDetail']?['ITEM_NAME'] ?? '이름없음';
      final aComb = List<Map<String, dynamic>>.from(a['dur']?['combination'] ?? []);

      for (int j = i + 1; j < entries.length; j++) {
        final b = entries[j].value;
        final bName = b['permit']?['permitDetail']?['ITEM_NAME'] ?? '이름없음';

        for (var combo in aComb) {
          final mixture = combo['mixtureItemName'] ?? '';
          if (mixture.toString().contains(bName)) {
            found = true;
            final reason = combo['prohibitContent'] ?? '이유 미상';
            debugPrint("🚫 금기 조합 발견: $aName × $bName ($reason)");
            await _speak("$aName과 $bName은 병용이 금기입니다. 이유는 $reason 입니다.");
          }
        }
      }
    }

    if (!found) {
      await _speak("선택하신 약들 사이에서 병용금기 조합은 발견되지 않았습니다.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("${widget.type} 검사"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.yellowAccent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hearing, color: Colors.yellowAccent, size: 64),
              const SizedBox(height: 20),
              Text(
                _getStepDescription(),
                style: const TextStyle(color: Colors.white70, fontSize: 18, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              if (isListening)
                const Text("🎙 듣는 중...", style: TextStyle(color: Colors.greenAccent))
              else
                ElevatedButton.icon(
                  onPressed: _listenForSpeech,
                  icon: const Icon(Icons.mic, color: Colors.black),
                  label: const Text("음성 다시 입력", style: TextStyle(color: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellowAccent,
                    minimumSize: const Size(200, 48),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStepDescription() {
    switch (step) {
      case InteractionStep.intro:
        return "화면 진입 중...";
      case InteractionStep.firstDrug:
        return "첫 번째 약 이름을 말씀해주세요.";
      case InteractionStep.selectDrug:
        return "검색된 약 중 하나를 선택해주세요.";
      case InteractionStep.addMore:
        return "추가로 검색할 약이 있으신가요?";
      case InteractionStep.finalConfirm:
        return "서버로 정보를 전송할까요?";
      case InteractionStep.result:
        return "결과 안내가 완료되었습니다.";
      default:
        return "";
    }
  }
}