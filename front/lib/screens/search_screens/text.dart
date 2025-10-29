import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../details/drug_detail.dart';
import '/api_services/api_helper.dart';
import '/services/settings_service.dart';

class TextSearchScreen extends StatefulWidget {
  const TextSearchScreen({super.key});

  @override
  State<TextSearchScreen> createState() => _TextSearchScreenState();
}

class _TextSearchScreenState extends State<TextSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FlutterTts tts = FlutterTts();
  final Dio dio = Dio();

  List<dynamic>? _items;
  bool _isLoading = false;
  bool _ttsEnabled = true;
  bool _highContrast = false;
  double _fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadAccessibilitySettings();
    _initVoiceGuide();
  }

  Future<void> _loadAccessibilitySettings() async {
    _ttsEnabled = await SettingsService.isVoiceGuideEnabled();
    _highContrast = await SettingsService.isHighContrastEnabled();
    _fontScale = await SettingsService.getFontScale();
    setState(() {});
  }

  Future<void> _initVoiceGuide() async {
    if (_ttsEnabled) {
      await tts.setLanguage("ko-KR");
      await tts.setSpeechRate(0.45);
      await tts.speak("텍스트 검색 페이지입니다. 약 이름을 입력한 뒤 검색 버튼을 눌러주세요.");
    }
  }

  Future<void> _speak(String text) async {
    if (!_ttsEnabled) return;
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    await tts.stop();
    await tts.speak(text);
  }

  /// ✨ 접근성용 글자 크기 스케일
  TextStyle scaled(double size,
      {FontWeight? weight, Color? color, double? height}) {
    return TextStyle(
      fontSize: size * _fontScale,
      fontWeight: weight,
      color: color ?? Colors.white,
      height: height ?? 1.4,
    );
  }

  /// 🎨 테마 색상 (voice.dart 동일)
  ColorScheme get _scheme => _highContrast
      ? const ColorScheme.dark(
          background: Colors.black,
          primary: Colors.amberAccent,
          onPrimary: Colors.black,
        )
      : const ColorScheme.dark(
          background: Color(0xFF1C1C1C),
          primary: Color(0xFFFFD700),
          onPrimary: Colors.black,
        );

  Future<void> _searchDrug() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      await _speak("약 이름을 입력해주세요.");
      return;
    }

    setState(() {
      _isLoading = true;
      _items = null;
    });

    await Vibration.vibrate(duration: 100);
    await _speak("$keyword 약을 검색합니다.");

    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      if (baseUrl.isEmpty) throw Exception("API_BASE_URL이 비어있습니다.");

      final url = "$baseUrl/keyword-search";
      final headers = await ApiHelper.getAuthHeaders();

      final response = await dio.get(
        url,
        queryParameters: {"keyword": keyword.replaceAll(" ", "")},
        options: Options(headers: headers),
      );

      final items = response.data["results"]?["items"] ??
          response.data["items"] ??
          [];

      setState(() {
        _isLoading = false;
        _items = items;
      });

      if (items.isEmpty) {
        await _speak("검색 결과가 없습니다. 다시 입력해주세요.");
      } else {
        await Vibration.vibrate(duration: 150);
        String listSpeech = items.map((e) => e["itemName"] ?? "").join(", ");
        await _speak("검색 결과입니다. $listSpeech 중에서 원하는 약을 선택하세요.");
        await _showSearchResultsPopup(items);
      }
    } catch (e, stack) {
      setState(() => _isLoading = false);
      debugPrint("❌ 오류: $e\n$stack");
      await _speak("약 정보를 불러오지 못했습니다. 다시 시도해주세요.");
    }
  }

  Future<void> _openDrugDetail(dynamic item) async {
    final name = item["itemName"] ?? "이름 정보 없음";
    await _speak("$name을 선택하셨습니다. 상세 정보를 보여드리겠습니다.");
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrugDetailScreen(
          initialDrugInfo: {"itemSeq": item["itemSeq"] ?? 'unknown'},
        ),
      ),
    );
  }

  Future<void> _showSearchResultsPopup(List<dynamic> items) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.95),
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
                      final item = items[index];
                      final name = item['itemName'] ?? '이름없음';
                      final company = item['entpName'] ?? '';
                      final imageUrl = item['imageUrl'];

                      return GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await _openDrugDetail(item);
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
                                  child: Image.network(
                                    imageUrl,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  ),
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
                Text(
                  _ttsEnabled
                      ? "음성 안내가 활성화되어 있습니다."
                      : "음성 안내가 비활성화되어 있습니다.",
                  style: scaled(14, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    tts.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = _scheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: Text(
          '텍스트로 약 검색',
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
              crossAxisAlignment: CrossAxisAlignment.center, // ✅ 중앙 정렬 추가
              children: [
                TextField(
                  controller: _controller,
                  style: scaled(18),
                  decoration: InputDecoration(
                    labelText: '약 이름 입력',
                    labelStyle: scaled(16, color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: scheme.primary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: scheme.primary, width: 2),
                    ),
                    fillColor: Colors.grey[900],
                    filled: true,
                  ),
                  onTap: () async {
                    if (_ttsEnabled)
                      await _speak("검색할 약 이름을 입력하세요.");
                  },
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.search, color: Colors.black),
                  label: Text(
                    '검색하기',
                    style: scaled(20,
                        weight: FontWeight.bold, color: Colors.black),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isLoading ? null : _searchDrug,
                ),
                const SizedBox(height: 30),
                if (_isLoading)
                  Column(
                    children: [
                      const CircularProgressIndicator(color: Colors.yellow),
                      const SizedBox(height: 16),
                      Text('검색 중...',
                          style: scaled(16, color: Colors.white70)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}