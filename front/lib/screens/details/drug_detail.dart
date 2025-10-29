import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../api_services/api_helper.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

class DrugDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? initialDrugInfo;
  const DrugDetailScreen({super.key, this.initialDrugInfo});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  final FlutterTts tts = FlutterTts();

  Map<String, dynamic>? detailData;
  String? _itemSeq;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setupTTS();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_itemSeq == null && _loading) {
      _resolveItemSeqAndFetch();
    }
  }

  Future<void> _setupTTS() async {
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    await tts.awaitSpeakCompletion(true);
  }

  void _resolveItemSeqAndFetch() {
    try {
      final routeArgs = ModalRoute.of(context)?.settings.arguments;
      Map<String, dynamic>? args;
      if (routeArgs is Map) {
        args = routeArgs.map((k, v) => MapEntry(k.toString(), v));
      }

      final candidate = widget.initialDrugInfo?['itemSeq'] ??
          widget.initialDrugInfo?['ITEM_SEQ'] ??
          args?['itemSeq'] ??
          args?['ITEM_SEQ'] ??
          args?['id'];

      final seq = candidate?.toString().trim();
      if (seq == null || seq.isEmpty) {
        _fail("약 코드(itemSeq)가 전달되지 않았습니다.");
        return;
      }

      setState(() => _itemSeq = seq);
      _fetchDrugDetail(seq);
    } catch (e) {
      _fail("인자 해석 중 오류가 발생했습니다.");
    }
  }

  Future<void> _fetchDrugDetail(String itemSeq) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      if (baseUrl.isEmpty) {
        _fail("API_BASE_URL이 설정되지 않았습니다.");
        return;
      }

      final uri = Uri.parse('$baseUrl/api/v3/log');
      final headers = await ApiHelper.getAuthHeaders();

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode([itemSeq]),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final results = decoded["results"];
        print("📡 서버 응답: $decoded");

        if (results is Map && results.isNotEmpty) {
          final key = results.keys.first;
          final first = results[key];
          print("🎯 파싱된 약 데이터: $first");

          if (first is Map<String, dynamic>) {
            setState(() {
              detailData = first;
              _loading = false;
            });

            Future.delayed(const Duration(milliseconds: 500), () async {
              await _speak("약 상세 정보 화면입니다. 아래로 스와이프하여 항목을 탐색할 수 있습니다.");
              await _speakSummary(first);
            });
            return;
          }
        }
        _fail("서버 응답에 약 상세 정보가 없습니다.");
      } else {
        _fail("서버 오류 (${response.statusCode})");
      }
    } catch (e) {
      _fail("약 정보 조회 중 오류가 발생했습니다.");
    }
  }

  void _fail(String message) async {
    setState(() {
      _loading = false;
      _error = message;
      detailData = null;
    });
    await _speak(message);
  }

  Future<void> _speak(String text) async {
    await tts.stop();
    await tts.speak(text);
  }

  Future<void> _speakSummary(Map<String, dynamic> data) async {
    final permit = data["permit"] ?? {};
    final permitDetail = permit["permitDetail"] ?? {};
    final permitList = permit["permitList"] ?? {};

    final name = permitList["itemName"] ??
        permitDetail["ITEM_NAME"] ??
        "이름 정보 없음";
    final entp = permitList["entpName"] ??
        permitDetail["ENTP_NAME"] ??
        "제조사 정보 없음";

    final effectList = data["edrug"]?["effect"];
    String effect;
    if (effectList is List && effectList.isNotEmpty) {
      effect = effectList.first.toString();
    } else {
      effect = permitDetail["EE_TEXT"] ?? "효능 정보 없음";
    }

    final cleaned = effect.replaceAll('\u0000', '');
    await _speak("이 약은 $name 입니다. 제조사는 $entp 입니다. 주요 효능은 $cleaned 입니다.");
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

    if (_loading) {
      return Scaffold(
        backgroundColor: scheme.background,
        appBar: AppBar(
          title: const Text("약 상세 정보"),
          backgroundColor: scheme.background,
          foregroundColor: scheme.primary,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.yellowAccent),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: scheme.background,
        appBar: AppBar(
          title: const Text("약 상세 정보"),
          backgroundColor: scheme.background,
          foregroundColor: scheme.primary,
        ),
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 18)),
        ),
      );
    }

    final data = detailData!;
    final permit = data["permit"]?["permitList"] ??
        data["permit"]?["permitDetail"] ??
        {};
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
              label: "약 기본 정보",
              child: Text(
                (permit["itemName"] ?? permit["ITEM_NAME"] ?? "이름 없음").toString(),
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "제조사: ${permit["entpName"] ?? permit["ENTP_NAME"] ?? "정보 없음"}",
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              "분류: ${permit["prductType"] ?? "정보 없음"}",
              style: const TextStyle(color: Colors.white70),
            ),
            const Divider(color: Colors.white24, height: 30),

            _buildAccessibleButton(context, "효능 및 효과",
                edrug["effect"] ?? permit["permitDetail"]?["EE_TEXT"]),
            _buildAccessibleButton(context, "용법 및 용량",
                edrug["dosage"] ?? permit["permitDetail"]?["UD_TEXT"]),
            _buildAccessibleButton(context, "주의사항",
                edrug["precautions"] ?? permit["permitDetail"]?["NB_TEXT"]),
            _buildAccessibleButton(context, "부작용", edrug["sideEffects"]),
            _buildAccessibleButton(context, "병용금기 및 상호작용",
                edrug["interactions"]),

            const Divider(color: Colors.white30, height: 40),
            const Text("DUR 금기 정보", style: TextStyle(color: Colors.white70, fontSize: 16)),
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
        onPressed: () {
          if (detailData != null) _speakSummary(detailData!);
        },
        tooltip: "약 요약 다시 듣기",
        child: const Icon(Icons.volume_up),
      ),
    );
  }

  Widget _buildAccessibleButton(BuildContext context, String title, dynamic contentList) {
    print("🧩 [$title] contentList type: ${contentList.runtimeType} → $contentList");

    if (contentList == null ||
        (contentList is List && contentList.isEmpty) ||
        (contentList is String && contentList.trim().isEmpty) ||
        (contentList is Map && contentList.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            "❌ $title 정보가 없습니다.",
            style: const TextStyle(color: Colors.white60, fontSize: 16),
          ),
        ),
      );
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
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

    final List<String> list;
    if (widget.contents is List) {
      list = (widget.contents as List).map((e) => e.toString()).toList();
    } else if (widget.contents is Map) {
      list = (widget.contents as Map).entries.map((e) => "${e.key}: ${e.value}").toList();
    } else {
      list = [widget.contents.toString()];
    }

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final content = list[index].replaceAll('\u0000', '');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                content,
                style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.black,
        tooltip: "내용 다시 듣기",
        onPressed: () => _speak("${widget.title} 내용을 다시 들려드리겠습니다."),
        child: const Icon(Icons.volume_up),
      ),
    );
  }
}