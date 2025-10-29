import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:provider/provider.dart';
import '/api_services/api_helper.dart';
import '/services/theme_service.dart';
import '/widgets/accessible_scaffold.dart';
import '/widgets/loading_widget.dart';
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
  bool _isSearching = false;
  String? _errorMessage;

  List<Map<String, dynamic>> searchResults = [];
  String? currentKeyword;

  @override
  void initState() {
    super.initState();
    _startIntro();
  }

  Future<void> _speak(String text, {bool listenAfter = false}) async {
    final theme = context.read<ThemeService>();
    if (!theme.isVoiceGuideEnabled) {
      if (listenAfter) await _listenForSpeech();
      return;
    }

    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    await tts.stop();
    await tts.speak(text);

    if (listenAfter) {
      // ✅ 안내음성이 완전히 끝난 뒤에만 STT 시작
      tts.setCompletionHandler(() async {
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 300));
        await Vibration.vibrate(duration: 100);
        await _listenForSpeech();
      });
    }
  }

  Future<void> _startIntro() async {
    final theme = context.read<ThemeService>();
    if (!theme.isVoiceGuideEnabled) {
      await Future.delayed(const Duration(milliseconds: 800));
      await _listenForSpeech();
      return;
    }
    await _speak("음성 검색 페이지입니다. 찾으시는 약품을 말씀해주세요.", listenAfter: true);
  }

  Future<void> _listenForSpeech() async {
    if (isListening || isBusy) return;

    setState(() {
      isListening = true;
    });

    final available = await sttInstance.initialize(
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
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    final cleanedKeyword = keyword.replaceAll(" ", "");

    // 🔊 먼저 "검색합니다" 안내 후 API 호출
    await _speak("$keyword 약을 검색합니다.");

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
        final names = items
            .map((e) => (e["itemName"] as String? ?? "이름없음").replaceAll(RegExp(r'\\(.*?\\)'), ''))
            .join(", ");
        // ✅ “검색 결과입니다. ~ 중 어떤 약을 선택하시겠습니까?”
        await _speak(
          "검색 결과입니다. $names 중 어떤 약을 선택하시겠습니까?",
          listenAfter: true,
        );

        // 🔔 팝업은 음성보다 살짝 나중에 뜨게
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _showSearchResultsPopup(items);
        });
      } else {
        await _speak("서버 응답이 올바르지 않습니다. 다시 시도해주세요.", listenAfter: true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "검색 중 오류가 발생했습니다: ${e.toString()}";
      });
      await _speak("검색 중 오류가 발생했습니다. 네트워크를 확인해주세요.", listenAfter: true);
    } finally {
      setState(() {
        _isSearching = false;
      });
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
        return Consumer<ThemeService>(
          builder: (context, theme, child) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "검색 결과",
                      style: theme.titleStyle.copyWith(
                        fontSize: 24 * theme.fontScale,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final drug = items[index];
                          final name = drug["itemName"] ?? "이름없음";
                          final company = drug["entpName"] ?? "";

                          return GestureDetector(
                            onTap: () async {
                              Navigator.pop(context);
                              await _onDrugSelected(drug);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: theme.buttonColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: theme.primaryColor,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.medication,
                                        color: Colors.grey),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: theme.buttonTextStyle.copyWith(
                                            fontSize: 18 * theme.fontScale,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          company,
                                          style: theme.bodyTextStyle.copyWith(
                                            fontSize: 14 * theme.fontScale,
                                            color: theme.buttonTextColor
                                                .withOpacity(0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right,
                                      color: Colors.grey),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "음성으로도 약 이름을 말씀하실 수 있습니다.",
                      style: theme.bodyTextStyle.copyWith(
                        fontSize: 14 * theme.fontScale,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _selectDrug(String input) async {
    if (searchResults.isEmpty) return;

    final drugNames =
        searchResults.map((e) => e["itemName"] as String? ?? "").toList();
    final bestMatch = StringSimilarity.findBestMatch(input, drugNames);

    if ((bestMatch.bestMatch.rating ?? 0) > 0.3) {
      final selectedDrug = searchResults[bestMatch.bestMatchIndex];
      await _onDrugSelected(selectedDrug);
    } else {
      await _speak("일치하는 약을 찾을 수 없습니다. 다시 말씀해주세요.", listenAfter: true);
    }
  }

  Future<void> _onDrugSelected(Map<String, dynamic> drug) async {
    await _speak("${drug["itemName"]} 약을 선택했습니다.");
    Vibration.vibrate(duration: 200);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DrugDetailScreen(initialDrugInfo: drug),
        ),
      );
    }
  }

  @override
  void dispose() {
    tts.stop();
    sttInstance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '음성 검색',
          body: _isSearching
              ? const LoadingWidget(message: "검색중입니다...")
              : _errorMessage != null
                  ? CustomErrorWidget(
                      message: _errorMessage!,
                      onRetry: () {
                        setState(() {
                          _errorMessage = null;
                        });
                      },
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.hearing,
                              size: 80 * theme.fontScale,
                              color: theme.primaryColor,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _getCurrentStatus(),
                              textAlign: TextAlign.center,
                              style: theme.bodyTextStyle.copyWith(
                                fontSize: 18 * theme.fontScale,
                              ),
                            ),
                            const SizedBox(height: 30),
                            if (isListening)
                              Text(
                                "듣는 중...",
                                style: theme.bodyTextStyle.copyWith(
                                  fontSize: 16 * theme.fontScale,
                                  color: Colors.greenAccent,
                                ),
                              )
                            else if (isBusy)
                              Text(
                                "처리 중...",
                                style: theme.bodyTextStyle.copyWith(
                                  fontSize: 16 * theme.fontScale,
                                  color: Colors.amber,
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                onPressed: _listenForSpeech,
                                icon: Icon(
                                  Icons.mic,
                                  color: theme.buttonTextColor,
                                  size: 24 * theme.fontScale,
                                ),
                                label: Text(
                                  "다시 듣기",
                                  style: theme.buttonTextStyle.copyWith(
                                    fontSize: 18 * theme.fontScale,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  minimumSize: Size(
                                      220 * theme.fontScale,
                                      52 * theme.fontScale),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
        );
      },
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