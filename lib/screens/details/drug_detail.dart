import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../api_services/api_helper.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

class DrugDetailScreen extends StatefulWidget {
  final Map<String, dynamic> drugInfo; // {"itemSeq": "195900043"}
  const DrugDetailScreen({super.key, required this.drugInfo});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  final FlutterTts tts = FlutterTts();
  Map<String, dynamic>? detailData;

  @override
  void initState() {
    super.initState();
    _setupTTS();
    _fetchDrugDetail();
  }

  Future<void> _setupTTS() async {
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    await tts.awaitSpeakCompletion(true);
  }

  Future<void> _fetchDrugDetail() async {
    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final uri = Uri.parse('$baseUrl/api/v3/log');
      final headers = await ApiHelper.getAuthHeaders();

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode([widget.drugInfo["itemSeq"]]),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final results = decoded["results"] ?? {};
        if (results.isNotEmpty) {
          final first = results.values.first;
          setState(() => detailData = first);

          await Future.delayed(const Duration(milliseconds: 800));
          await _speak("약 상세 정보 화면입니다. 아래로 스와이프하여 항목을 탐색할 수 있습니다. 각 항목을 두 번 탭하면 세부 내용을 들을 수 있습니다.");
          await _speakSummary(first);
        } else {
          await _speak("약 정보를 불러오지 못했습니다.");
        }
      } else {
        await _speak("서버에서 정보를 불러오지 못했습니다.");
      }
    } catch (e) {
      await _speak("약 정보 조회 중 오류가 발생했습니다.");
    }
  }

  Future<void> _speak(String text) async {
    await tts.stop();
    await tts.speak(text);
  }

  Future<void> _speakSummary(Map<String, dynamic> data) async {
    final name = data["permit"]?["permitList"]?["itemName"] ?? "이름 정보 없음";
    final entp = data["permit"]?["permitList"]?["entpName"] ?? "제조사 정보 없음";
    final effectList = data["edrug"]?["effect"];
    final effect = (effectList != null && effectList.isNotEmpty)
        ? effectList.first
        : "효능 정보 없음";

    await _speak(
      "이 약은 $name 입니다. 제조사는 $entp 입니다. 주요 효능은 ${effect.replaceAll('\u0000', '')} 입니다. 세부 항목을 탐색하려면 아래로 스와이프하세요.",
    );
  }

  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      background: Colors.black,
      primary: Color(0xFFFFEB3B),
      onPrimary: Colors.black,
    );

    final data = detailData;
    if (data == null) {
      return Scaffold(
        backgroundColor: scheme.background,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.yellowAccent),
        ),
      );
    }

    final permit = data["permit"]?["permitList"] ?? {};
    final edrug = data["edrug"] ?? {};
    final dur = data["dur"] ?? {};

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: const Text("약 상세 정보"),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Semantics(
              header: true,
              focusable: true,
              label: "약 기본 정보 제목",
              hint: "약 이름과 제조사 등의 기본 정보를 포함합니다.",
              child: Text(
                permit["itemName"] ?? "이름 없음",
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "제조사: ${permit["entpName"] ?? "정보 없음"}",
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              "분류: ${permit["prductType"] ?? "정보 없음"}",
              style: const TextStyle(color: Colors.white70),
            ),
            const Divider(color: Colors.white24, height: 30),

            Semantics(
              header: true,
              focusable: true,
              label: "일반 의약 정보 섹션",
              hint: "효능, 용법, 주의사항 등을 포함합니다.",
              child: const Text(
                "일반 의약 정보",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            _buildAccessibleButton(context, "효능 및 효과", edrug["effect"]),
            _buildAccessibleButton(context, "용법 및 용량", edrug["dosage"]),
            _buildAccessibleButton(context, "주의사항", edrug["precautions"]),
            _buildAccessibleButton(context, "병용금기 및 상호작용", edrug["interactions"]),
            _buildAccessibleButton(context, "부작용", edrug["sideEffects"]),

            const Divider(color: Colors.white30, height: 40),

            Semantics(
              header: true,
              focusable: true,
              label: "DUR 금기 정보 섹션",
              hint: "특정 연령, 임부, 노인, 투여 기간 등의 금기 정보를 포함합니다.",
              child: const Text(
                "DUR 금기 정보",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            _buildAccessibleButton(context, "병용금기", dur["combination"]),
            _buildAccessibleButton(context, "노인금기", dur["elderly"]),
            _buildAccessibleButton(context, "임부금기", dur["pregnant"]),
            _buildAccessibleButton(context, "특정연령금기", dur["age"]),
            _buildAccessibleButton(context, "용량금기", dur["dosage"]),
            _buildAccessibleButton(context, "투여기간금기", dur["term"]),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        onPressed: () => _speakSummary(data),
        tooltip: "약 요약 다시 듣기",
        child: const Icon(Icons.volume_up),
      ),
    );
  }

  Widget _buildAccessibleButton(BuildContext context, String title, dynamic contentList) {
    if (contentList == null ||
        (contentList is List && contentList.isEmpty) ||
        (contentList is Map && contentList.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        button: true,
        focusable: true,
        label: "$title 버튼",
        hint: "이 항목의 내용을 들으려면 두 번 탭하세요.",
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF222222),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
            overlayColor: Colors.yellow.withOpacity(0.2),
          ),
          onPressed: () async {
            await _speak("$title 내용을 읽습니다.");
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DrugDetailSubPage(title: title, contents: contentList),
              ),
            );
          },
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 18)),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class DrugDetailSubPage extends StatefulWidget {
  final String title;
  final dynamic contents;
  const DrugDetailSubPage({super.key, required this.title, required this.contents});

  @override
  State<DrugDetailSubPage> createState() => _DrugDetailSubPageState();
}

class _DrugDetailSubPageState extends State<DrugDetailSubPage> {
  final FlutterTts tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _setupTTS();
      await _speak("${widget.title} 화면입니다. 아래로 스와이프하여 내용을 탐색하세요.");
    });
  }

  Future<void> _setupTTS() async {
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.5);
    await tts.awaitSpeakCompletion(true);
  }

  Future<void> _speak(String text) async {
    await tts.stop();
    await tts.speak(text);
  }

  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      background: Colors.black,
      primary: Color(0xFFFFEB3B),
    );

    final list = widget.contents is List
        ? (widget.contents as List)
        : [widget.contents.toString()];

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          focusable: true,
          label: "${widget.title} 세부 내용 영역",
          hint: "화면을 아래로 스와이프하여 각 문장을 들을 수 있습니다.",
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final content = list[index].toString().replaceAll('\u0000', '');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(
                  label: "${widget.title} ${index + 1}번째 문장",
                  child: Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        tooltip: "내용 다시 듣기",
        onPressed: () => _speak("${widget.title} 내용을 다시 들려드리겠습니다."),
        child: const Icon(Icons.volume_up),
      ),
    );
  }
}