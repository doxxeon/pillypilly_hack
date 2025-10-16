import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:string_similarity/string_similarity.dart';
import '/api_services/api_helper.dart';
import '/services/settings_service.dart';
import '../details/drug_detail.dart';

class VoiceSearchScreen extends StatefulWidget {
  const VoiceSearchScreen({super.key});

  @override
  State<VoiceSearchScreen> createState() => _VoiceSearchScreenState();
}

class _VoiceSearchScreenState extends State<VoiceSearchScreen> {
  final FlutterTts tts = FlutterTts();
  final stt.SpeechToText sttInstance = stt.SpeechToText();
  final Dio dio = Dio();

  bool isListening = false;
  bool isBusy = false;
  bool _ttsEnabled = true;
  bool _highContrast = false;
  double _fontScale = 1.0;

  List<Map<String, dynamic>> searchResults = [];
  String? currentKeyword;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startIntro();
  }

  Future<void> _loadSettings() async {
    _ttsEnabled = await SettingsService.isVoiceGuideEnabled();
    _highContrast = await SettingsService.isHighContrastEnabled();
    _fontScale = await SettingsService.getFontScale();
    setState(() {});
  }

  /// 🎨 컬러 테마 지정
  ColorScheme get _scheme => _highContrast
      ? const ColorScheme.dark(
          background: Colors.black,
          primary: Colors.amberAccent,
          onPrimary: Colors.black,
        )
      : const ColorScheme.dark(
          background: Color(0xFF1C1C1C), // 짙은 회색
          primary: Color(0xFFFFD700), // 노란색 포인트
          onPrimary: Colors.black,
        );

  TextStyle scaled(double size,
      {FontWeight? weight, Color? color, double? height}) {
    return TextStyle(
      fontSize: size * _fontScale,
      fontWeight: weight,
      color: color ?? Colors.white,
      height: height ?? 1.4,
    );
  }

  Future<void> _speak(String text, {bool listenAfter = false}) async {
    if (!_ttsEnabled) {
      if (listenAfter) await _listenForSpeech();
      return;
    }
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    await tts.stop();
    await tts.speak(text);

    tts.setCompletionHandler(() async {
      if (listenAfter && mounted) {
        await tts.speak("지금부터 말씀해주세요.");
        tts.setCompletionHandler(() async {
          await Vibration.vibrate(duration: 150);
          await Future.delayed(const Duration(milliseconds: 250));
          await _listenForSpeech();
        });
      }
    });
  }

  Future<void> _startIntro() async {
    if (!_ttsEnabled) {
      await Future.delayed(const Duration(milliseconds: 800));
      await _listenForSpeech();
      return;
    }
    await _speak("음성 검색 페이지입니다. 찾으시는 약품을 말씀해주세요.", listenAfter: true);
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

  Future<void> _handleSpeechInput(String input) async {
    await sttInstance.stop();
    setState(() {
      isListening = false;
      isBusy = true;
    });

    if (input.isEmpty) {
      await _speak("음성이 인식되지 않았습니다. 다시 말씀해주세요.", listenAfter: true);
      setState(() => isBusy = false);
      return;
    }

    if (currentKeyword == null) {
      currentKeyword = input;
      await _searchDrug(input);
    } else {
      await _selectDrug(input);
    }

    setState(() => isBusy = false);
  }

  Future<void> _searchDrug(String keyword) async {
    await _speak("$keyword 약을 검색합니다.");
    final cleanedKeyword = keyword.replaceAll(" ", "");

    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = "$baseUrl/keyword-search";
      final headers = await ApiHelper.getAuthHeaders();

      final response = await dio.get(
        url,
        queryParameters: {"keyword": cleanedKeyword},
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final items =
            List<Map<String, dynamic>>.from(data["results"]["items"] ?? []);
        if (items.isEmpty) {
          await _speak("검색 결과가 없습니다. 다시 말씀해주세요.", listenAfter: true);
          currentKeyword = null;
          return;
        }

        searchResults = items;
        final names = items.map((e) => e["itemName"] ?? "이름없음").join(", ");
        await _showSearchResultsPopup(items);
        await _speak(
            "검색 결과입니다. $names 중에서 선택하실 약의 이름을 말씀해주세요.",
            listenAfter: true);
      } else {
        await _speak("서버 응답이 올바르지 않습니다. 다시 시도해주세요.", listenAfter: true);
      }
    } catch (e) {
      await _speak("검색 중 오류가 발생했습니다. 네트워크를 확인해주세요.", listenAfter: true);
    }
  }

  Future<void> _showSearchResultsPopup(List<Map<String, dynamic>> items) async {
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.95),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("검색 결과",
                    style: scaled(24,
                        weight: FontWeight.bold, color: _scheme.primary)),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final drug = items[index];
                      final name = drug["itemName"] ?? "이름없음";
                      final company = drug["entpName"] ?? "";
                      final imageUrl = drug["imageUrl"];

                      return GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await _onDrugSelected(drug);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: _scheme.primary, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              if (imageUrl != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(imageUrl,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover),
                                )
                              else
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[800],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.medication_outlined,
                                      color: Colors.white70, size: 32),
                                ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: scaled(18,
                                            weight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(company,
                                        style: scaled(14,
                                            color: Colors.white70)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text("음성으로도 약 이름을 말씀하실 수 있습니다.",
                    style: scaled(14, color: Colors.grey)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onDrugSelected(Map<String, dynamic> drug) async {
    await Vibration.vibrate(duration: 120);
    await _speak("${drug["itemName"]}을 선택하셨습니다. 상세 정보를 보여드리겠습니다.");
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DrugDetailScreen(
            drugInfo: {"itemSeq": drug["itemSeq"] ?? 'unknown'},
          ),
        ),
      );
    }
  }

  Future<void> _selectDrug(String input) async {
    final cleanedInput = input.replaceAll(" ", "");
    Map<String, dynamic>? matched;

    for (final item in searchResults) {
      final name = (item["itemName"] as String).replaceAll(" ", "");
      if (name.contains(cleanedInput)) {
        matched = item;
        break;
      }
    }

    if (matched == null) {
      double best = 0.0;
      for (final item in searchResults) {
        final name = (item["itemName"] as String).replaceAll(" ", "");
        final sim = name.similarityTo(cleanedInput);
        if (sim > best && sim > 0.8) {
          best = sim;
          matched = item;
        }
      }
    }

    if (matched == null) {
      await _speak("해당 이름의 약을 찾지 못했습니다. 다시 말씀해주세요.", listenAfter: true);
      return;
    }
    await _onDrugSelected(matched);
  }

  @override
  void dispose() {
    tts.stop();
    sttInstance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = _scheme;
    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: Text(
          "음성 검색",
          style: scaled(20, weight: FontWeight.bold, color: scheme.primary),
        ),
        centerTitle: true,
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center, // ✅ 중앙 정렬 보정
              children: [
                Icon(Icons.hearing, size: 80, color: scheme.primary),
                const SizedBox(height: 24),
                Text(
                  _getCurrentStatus(),
                  textAlign: TextAlign.center,
                  style: scaled(18, color: Colors.white70),
                ),
                const SizedBox(height: 30),
                if (isListening)
                  Text("듣는 중...", style: scaled(16, color: Colors.greenAccent))
                else if (isBusy)
                  Text("처리 중...", style: scaled(16, color: Colors.amber))
                else
                  ElevatedButton.icon(
                    onPressed: _listenForSpeech,
                    icon: const Icon(Icons.mic, color: Colors.black),
                    label: Text("다시 듣기",
                        style: scaled(18,
                            weight: FontWeight.bold, color: Colors.black)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      minimumSize: const Size(220, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getCurrentStatus() {
    if (currentKeyword == null) {
      return "찾으시는 약의 이름을 말씀해주세요.";
    } else {
      return "검색 결과 중 선택하실 약 이름을 말씀해주세요.";
    }
  }
}