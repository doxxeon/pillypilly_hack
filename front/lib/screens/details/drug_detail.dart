// front/lib/screens/details/drug_detail.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../../api_services/api_helper.dart';

class DrugDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? initialDrugInfo;
  const DrugDetailScreen({super.key, this.initialDrugInfo});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

// ──────────────────────────────────────────────────────────────────────────
// 텍스트 스타일 (표시 규칙 전용: 라벨 굵게/본문 가독/Muted 등)
const TextStyle _bodyStyle = TextStyle(
  color: Colors.white,
  fontSize: 18,
  height: 1.6,
);

const TextStyle _mutedStyle = TextStyle(
  color: Colors.white70,
  fontSize: 18,
  height: 1.6,
);

const TextStyle _labelStyle = TextStyle(
  color: Colors.white,
  fontSize: 18,
  fontWeight: FontWeight.w700,
  height: 1.6,
);

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  final FlutterTts _tts = FlutterTts();

  // .env 에서 한 번만 읽어서 전체에서 사용
  late final String _baseUrl = dotenv.env['API_BASE_URL'] ?? '';

  Map<String, dynamic>? _detailData;
  String? _itemSeq;
  bool _loading = true;
  String? _error;

  String? _initialName;
  String? _initialEntp;

  String? _imageUrl;

  // 이미지 요청에도 같은 인증 헤더를 사용할 수 있도록 캐싱
  Map<String, String>? _imageHeaders;

  @override
  void initState() {
    super.initState();
    _setupTTS();

    _initialName = _str(widget.initialDrugInfo?['itemName']) ??
        _str(widget.initialDrugInfo?['ITEM_NAME']);
    _initialEntp = _str(widget.initialDrugInfo?['entpName']) ??
        _str(widget.initialDrugInfo?['ENTP_NAME']);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_itemSeq == null && _loading) {
      _resolveItemSeqAndFetch();
    }
  }

  Future<void> _setupTTS() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.45);
    await _tts.awaitSpeakCompletion(true);
  }

  void _resolveItemSeqAndFetch() {
    try {
      final routeArgs = ModalRoute.of(context)?.settings.arguments;
      Map<String, dynamic>? args;
      if (routeArgs is Map) {
        args = routeArgs.map((k, v) => MapEntry(k.toString(), v));
      }

      // 0. QR/바코드 화면에서 넘긴 drugInfo 처리
      Map<String, dynamic>? drugInfo;
      final rawDrugInfo = args != null ? args['drugInfo'] : null;
      if (rawDrugInfo is Map) {
        drugInfo = Map<String, dynamic>.from(rawDrugInfo);
      }

      // 1. 가장 단순한 케이스: 위젯 초기값 + routeArgs 최상단
      final primaryCandidate = widget.initialDrugInfo?['itemSeq'] ??
          widget.initialDrugInfo?['ITEM_SEQ'] ??
          widget.initialDrugInfo?['itemseq'] ??
          args?['itemSeq'] ??
          args?['ITEM_SEQ'] ??
          args?['itemseq'] ??
          args?['id'];

      String? seq = primaryCandidate?.toString().trim();

      // 2. drugInfo 맵 안에 itemSeq가 있는 경우 우선 시도
      if ((seq == null || seq.isEmpty) && drugInfo != null) {
        final fromDrugInfo = drugInfo['itemSeq'] ??
            drugInfo['ITEM_SEQ'] ??
            drugInfo['itemseq'] ??
            drugInfo['id'];
        if (fromDrugInfo != null && fromDrugInfo.toString().trim().isNotEmpty) {
          seq = fromDrugInfo.toString().trim();
        }
      }

      // 3. 그래도 없으면 전체 구조를 깊게 탐색
      if (seq == null || seq.isEmpty) {
        final merged = <String, dynamic>{};
        if (widget.initialDrugInfo != null) {
          merged.addAll(widget.initialDrugInfo!);
        }
        if (args != null) {
          merged.addAll(args);
        }
        if (drugInfo != null) {
          merged['drugInfo'] = drugInfo;
        }

        final deep = _findSeqFromAny(merged);
        if (deep != null && deep.trim().isNotEmpty) {
          seq = deep.trim();
        }
      }

      if (seq == null || seq.isEmpty) {
        _fail("약 코드(itemSeq)가 전달되지 않았습니다.");
        return;
      }

      setState(() => _itemSeq = seq);
      _fetchDrugDetail(seq);
    } catch (_) {
      _fail("인자 해석 중 오류가 발생했습니다.");
    }
  }

  String? _findSeqFromAny(dynamic data) {
    // 재귀적으로 어떤 깊이에 있든 itemSeq/ITEM_SEQ/id 를 찾아낸다.
    if (data is Map) {
      // 1차: 현재 맵에서 직접 키 탐색
      for (final key in ['itemSeq', 'ITEM_SEQ', 'itemseq', 'id']) {
        if (data.containsKey(key)) {
          final v = data[key];
          if (v != null && v.toString().trim().isNotEmpty) {
            return v.toString().trim();
          }
        }
      }

      // 2차: results 맵이 있고, key가 전부 숫자인 경우 → key 자체를 itemSeq로 사용
      final results = data['results'];
      if (results is Map && results.isNotEmpty) {
        final firstKey = results.keys.first.toString();
        if (RegExp(r'^\d+$').hasMatch(firstKey)) {
          return firstKey.trim();
        }
      }

      // 3차: 하위 값들 재귀적으로 순회
      for (final v in data.values) {
        final nested = _findSeqFromAny(v);
        if (nested != null && nested.trim().isNotEmpty) {
          return nested.trim();
        }
      }
    } else if (data is List) {
      for (final e in data) {
        final nested = _findSeqFromAny(e);
        if (nested != null && nested.trim().isNotEmpty) {
          return nested.trim();
        }
      }
    }

    return null;
  }

  Future<void> _fetchDrugDetail(String itemSeq) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_baseUrl.isEmpty) {
        _fail("API_BASE_URL이 설정되지 않았습니다.");
        return;
      }

      final uri = Uri.parse('$_baseUrl/api/v3/log');
      final headers = await ApiHelper.getAuthHeaders();

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode([itemSeq]),
      );

      if (response.statusCode != 200) {
        _fail("서버 오류 (${response.statusCode})");
        return;
      }

      final decoded = jsonDecode(response.body);
      final results = decoded["results"];
      Map<String, dynamic>? payload;
      if (results is Map && results.isNotEmpty) {
        final key = results.keys.first;
        final first = results[key];
        if (first is Map) payload = Map<String, dynamic>.from(first);
      }

      if (payload == null || payload.isEmpty) {
        _fail("서버 응답에 약 상세 정보가 없습니다.");
        return;
      }

      setState(() {
        _detailData = payload;
        _loading = false;
      });

      // 디버그: API 응답 구조 확인
      debugPrint('📋 [DrugDetail] API 응답 구조:');
      debugPrint('  - edrug: ${payload["edrug"]}');
      debugPrint('  - permit: ${payload["permit"]}');
      if (payload["edrug"] is Map) {
        final edrug = Map<String, dynamic>.from(payload["edrug"]);
        debugPrint('  - edrug["precautions"]: ${edrug["precautions"]}');
      }
      if (payload["permit"] is Map) {
        final permit = Map<String, dynamic>.from(payload["permit"]);
        if (permit["permitDetail"] is Map) {
          final permitDetail = Map<String, dynamic>.from(permit["permitDetail"]);
          debugPrint('  - permit["permitDetail"]["NB_TEXT"]: ${permitDetail["NB_TEXT"]}');
        }
      }

      _prepareImage(itemSeq, payload);

      Future.delayed(const Duration(milliseconds: 300), () async {
        await _speak("약 상세 정보 화면입니다. 아래로 스와이프하여 항목을 탐색할 수 있습니다.");
      });
    } catch (_) {
      _fail("약 정보 조회 중 오류가 발생했습니다.");
    }
  }

  Future<void> _prepareImage(String itemSeq, Map<String, dynamic> payload) async {
  // 1) 응답 안에서 바로 이미지 URL 있으면 그거 사용
  final permit = _bestPermit(payload);
  final Map<String, dynamic>? permitList =
      (payload["permit"] is Map && (payload["permit"]["permitList"] is Map))
          ? Map<String, dynamic>.from(payload["permit"]["permitList"])
          : null;
  final Map<String, dynamic> edrug =
      (payload["edrug"] is Map) ? Map<String, dynamic>.from(payload["edrug"]) : <String, dynamic>{};

  final existingUrl = _findImageUrl(payload, permit, permitList, edrug);

  if (existingUrl != null && existingUrl.isNotEmpty) {
    if (mounted) {
      setState(() => _imageUrl = existingUrl);
    }
    return;
  }

  // 2) 없으면 image-scrape API 호출해서 크롤링
  await _fetchImageFromScraper(itemSeq);
}

Future<void> _fetchImageFromScraper(String itemSeq) async {
  if (_baseUrl.isEmpty) return;

  try {
    final uri = Uri.parse('$_baseUrl/image-scrape?item_seq=$itemSeq');
    final headers = await ApiHelper.getAuthHeaders();

    // 이미지 요청에도 같은 인증 헤더를 사용할 수 있도록 캐싱
    if (mounted) {
      _imageHeaders = Map<String, String>.from(headers);
    }

    debugPrint('📸 [image-scrape] GET $uri');

    final resp = await http.get(uri, headers: headers);
    debugPrint('📸 [image-scrape] status = ${resp.statusCode}');

    if (resp.statusCode != 200) {
      // 422/500 등은 조용히 무시
      return;
    }

    // 1) 서버가 이미지 바이너리를 직접 내려주는 경우
    final contentType =
        resp.headers['content-type'] ?? resp.headers['Content-Type'] ?? '';
    if (contentType.startsWith('image/')) {
      final url = uri.toString();
      debugPrint('📸 [image-scrape] using endpoint as image url = $url');
      if (mounted) {
        setState(() => _imageUrl = url);
      }
      return;
    }

    // 2) 그 외에는 텍스트/JSON에서 URL 파싱 (UTF-8 실패시 resp.body로 폴백)
    String raw;
    try {
      raw = utf8.decode(resp.bodyBytes);
    } on FormatException {
      raw = resp.body;
    }
    raw = raw.trim();
    if (raw.isEmpty) return;

    String url = "";

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        url = (decoded['imageUrl'] ??
                decoded['url'] ??
                decoded['image'] ??
                decoded['image_url'] ??
                "")
            .toString();
      } else if (decoded is String) {
        url = decoded;
      } else {
        url = raw;
      }
    } catch (_) {
      // JSON 아니면 그냥 문자열 자체를 URL로 사용
      url = raw;
    }

    if (url.isEmpty) return;

    if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'https://');
    }
    debugPrint('📸 [image-scrape] final image url = $url');

    if (mounted) {
      setState(() => _imageUrl = url);
    }
  } catch (e, st) {
    // 네트워크 에러도 조용히 무시
    debugPrint('📸 [image-scrape] error: $e\n$st');
    return;
  }
}

  void _fail(String message) async {
    setState(() {
      _loading = false;
      _error = message;
      _detailData = null;
    });
    await _speak(message);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _tts.stop();
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
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final data = _detailData!;
    final permit = _bestPermit(data);
    // permitList 정의 추가
    final Map<String, dynamic>? permitList =
        (data["permit"] is Map && (data["permit"]["permitList"] is Map))
            ? Map<String, dynamic>.from(data["permit"]["permitList"])
            : null;
    
    // permitDetail 직접 추출 (실제 데이터가 여기에 있음)
    final Map<String, dynamic> permitDetail =
        (data["permit"] is Map && data["permit"]["permitDetail"] is Map)
            ? Map<String, dynamic>.from(data["permit"]["permitDetail"])
            : <String, dynamic>{};

    final Map<String, dynamic> edrug =
        (data["edrug"] is Map) ? Map<String, dynamic>.from(data["edrug"]) : <String, dynamic>{};
    final dur = data["dur"] ?? {};

    final displayName =
        _str(permit["itemName"]) ?? _str(permit["ITEM_NAME"]) ?? _str(permitDetail["ITEM_NAME"]) ?? _initialName ?? "이름 없음";
    final displayEntp =
        _str(permit["entpName"]) ?? _str(permit["ENTP_NAME"]) ?? _str(permitDetail["ENTP_NAME"]) ?? _initialEntp ?? "정보 없음";
    final productType = _str(permit["prductType"]) ?? _str(permitList?["prductType"]) ?? "정보 없음";

    // 🔥 여기서 이미지 URL 결론 냄: 1) 응답 안에서 찾고, 2) 없으면 image-scrape 사용
    final imageUrl = _imageUrl ??
    _findImageUrl(
      data,
      permit,
      permitList,
      edrug,
    );

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: const Text("약 상세 정보"),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              // ① 약 이름 위 이미지 (깊게 탐색 + http→https 보정 + image-scrape fallback)
              _topImage(imageUrl, headers: _imageHeaders),

              // 기본 정보
              Semantics(
                header: true,
                focusable: true,
                label: "약 기본 정보",
                child: Text(
                  displayName,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "제조사: $displayEntp",
                style: _mutedStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                "분류: $productType",
                style: _mutedStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(color: Colors.white24, height: 30),

              // ② 섹션 버튼 (UI 유지, 내용 표시만 가독형으로)
              // permitDetail을 우선 사용 (실제 데이터가 여기에 있음), 없으면 edrug 확인
              _a11yButton(
                context,
                title: "효능 및 효과",
                contents: _getContent(permitDetail["EE_TEXT"], edrug["effect"]),
              ),
              _a11yButton(
                context,
                title: "용법 및 용량",
                contents: _getContent(permitDetail["UD_TEXT"], edrug["dosage"]),
              ),
              _a11yButton(
                context,
                title: "주의사항",
                contents: _getContent(permitDetail["NB_TEXT"], edrug["precautions"]),
              ),
              _a11yButton(
                context,
                title: "부작용",
                contents: edrug["sideEffects"],
              ),
              _a11yButton(
                context,
                title: "병용금기 및 상호작용",
                contents: edrug["interactions"],
              ),

              const Divider(color: Colors.white30, height: 40),

              // DUR
              Semantics(
                label: "디유알 금기 정보",
                child: const Text(
                  "DUR 금기 정보",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              _a11yButton(context, title: "병용금기", contents: dur["combination"]),
              _a11yButton(context, title: "노인금기", contents: dur["elderly"]),
              _a11yButton(context, title: "임부금기", contents: dur["pregnant"]),
              _a11yButton(context, title: "특정연령금기", contents: dur["age"]),
              _a11yButton(context, title: "용량금기", contents: dur["dosage"]),
              _a11yButton(context, title: "투여기간금기", contents: dur["term"]),
            ],
          ),
        ),
      ),
    );
  }

  /// 여러 경로를 훑어 첫 이미지 URL을 찾고,
  /// 없으면 image-scrape 엔드포인트 URL을 fallback 으로 사용
  String? _findImageUrl(
    Map<String, dynamic> data,
    Map<String, dynamic> permit,
    Map<String, dynamic>? permitList,
    Map<String, dynamic> edrug, 
    ) 
  {
    String? _firstNonEmpty(Iterable<String?> xs) {
      for (final s in xs) {
        if (s != null && s.trim().isNotEmpty) return s.trim();
      }
      return null;
    }

    final candidates = <String?>[
      _str(permit["itemImage"]),
      _str(permit["ITEM_IMAGE"]),
      _str(permit["ITEM_IMAGE_PATH"]),
      _str(permitList?["imageUrl"]),
      _str(data["image"]),
      _str(data["thumbnail"]),
      _str(edrug["image"]),
      _str(edrug["thumbnail"]),
    ];

    String? url = _firstNonEmpty(candidates);

    if (url == null) return null;

    if (url.startsWith('http://')) {
      url = url.replaceFirst('http://', 'https://');
    }
    return url;
  }

  Widget _topImage(String? url, {Map<String, String>? headers}) {
    // 시각장애인 안내용, 이미지 없을 때도 뭔가가 있는 편이 좋음
    if (url == null || url.isEmpty) {
      return Semantics(
        label: "의약품 이미지가 제공되지 않았습니다.",
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.medication_outlined,
                  color: Colors.white54, size: 48),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: "의약품 이미지",
      image: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _NetworkImageSmart(url: url, headers: headers),
        ),
      ),
    );
  }

  Widget _a11yButton(
    BuildContext context, {
    required String title,
    required dynamic contents,
  }) {
    final empty = _isEmpty(contents);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        container: true,
        button: true,
        label: "$title 버튼",
        hint: empty ? "표시할 내용이 없습니다." : "이 항목의 내용을 보려면 두 번 탭하세요.",
        child: ExcludeSemantics(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF222222),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              overlayColor: Colors.yellowAccent.withOpacity(0.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: empty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DrugDetailSubPage(
                          title: title,
                          contents: contents,
                        ),
                      ),
                    );
                  },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _bestPermit(Map<String, dynamic> data) {
    final permit = data["permit"];
    if (permit is Map) {
      final list = permit["permitList"];
      final detail = permit["permitDetail"];
      if (list is Map && list.isNotEmpty) {
        return Map<String, dynamic>.from(list);
      }
      if (detail is Map && detail.isNotEmpty) {
        return Map<String, dynamic>.from(detail);
      }
    }
    return <String, dynamic>{};
  }

  String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool _isEmpty(dynamic v) {
    if (v == null) return true;
    if (v is String) return v.trim().isEmpty || v.trim() == '{}' || v.trim() == '[]';
    if (v is Iterable) return v.isEmpty;
    if (v is Map) return v.isEmpty;
    return false;
  }

  /// permitDetail의 내용을 우선 사용하고, 없거나 비어있으면 edrug의 내용을 반환
  dynamic _getContent(dynamic primary, dynamic fallback) {
    if (!_isEmpty(primary)) return primary;
    if (!_isEmpty(fallback)) return fallback;
    return null;
  }
}

/// 네트워크 이미지 로더 (http→https 대체 시도, 실패 시 숨김)
class _NetworkImageSmart extends StatelessWidget {
  final String url;
  final Map<String, String>? headers;
  const _NetworkImageSmart({required this.url, this.headers});

  @override
  Widget build(BuildContext context) {
    final tryUrl = url;
    return Image.network(
      tryUrl,
      width: double.infinity,
      height: 160,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      headers: headers,
      errorBuilder: (_, __, ___) {
        if (tryUrl.startsWith('http://')) {
          final https = tryUrl.replaceFirst('http://', 'https://');
          return Image.network(
            https,
            width: double.infinity,
            height: 160,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            headers: headers,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// 하위 페이지: 섹션 상세 “가독형 리스트” (DUR 라벨 매핑 포함)
class DrugDetailSubPage extends StatefulWidget {
  final String title;
  final dynamic contents;
  const DrugDetailSubPage({
    super.key,
    required this.title,
    required this.contents,
  });

  @override
  State<DrugDetailSubPage> createState() => _DrugDetailSubPageState();
}

class _DrugDetailSubPageState extends State<DrugDetailSubPage> {
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _setupTTS();
      await _speak("${widget.title} 화면입니다. 아래로 스와이프하여 내용을 탐색하세요.");
    });
  }

  Future<void> _setupTTS() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  // 메인 포맷터: String/List/Map → “읽기 좋은 문장 리스트”
  List<String> _toReadableList(String title, dynamic src) {
    final isDur = title.contains("금기") || title.contains("주의");

    if (src == null) return const [];

    if (src is String) {
      return _splitSentences(src);
    }

    if (src is List) {
      final out = <String>[];
      for (final item in src) {
        if (item is Map) {
          out.addAll(_fromMap(item, isDur: isDur));
        } else if (item != null) {
          out.addAll(_splitSentences(item.toString()));
        }
      }
      return _clean(out);
    }

    if (src is Map) {
      return _clean(_fromMap(src, isDur: isDur));
    }

    return _splitSentences(src.toString());
  }

  // 한국어 줄글 분리(+HTML 제거, 특수 불릿/줄바꿈 정리)
  String _stripHtml(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');

  List<String> _splitSentences(String text) {
    final t = _stripHtml(text);
    
    // \u0000은 띄어쓰기로 변환, \n은 줄바꿈으로 유지
    String cleaned = t.replaceAll('\u0000', ' ');
    
    // 연속된 공백을 하나로, 하지만 줄바꿈은 유지
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n'), '\n\n'); // 빈 줄 정리
    
    // 섹션 제목 패턴
    final sectionTitlePattern = RegExp(r'^(효능효과|용법용량|사용상의주의사항|주의사항|부작용|상호작용|임부|수유부|소아|고령자|과량|임상검사)');
    
    // 번호가 있는 항목을 더 명확하게 구분 (1., 2., 3. 등)
    // 줄바꿈이 있는 경우와 없는 경우 모두 처리
    final lines = cleaned.split('\n');
    final result = <String>[];
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        // 빈 줄은 구분선으로 사용
        if (result.isNotEmpty && result.last.isNotEmpty) {
          result.add(''); // 빈 줄 추가 (구분용)
        }
        continue;
      }
      
      // 섹션 제목 확인
      if (sectionTitlePattern.hasMatch(trimmed)) {
        // 섹션 제목은 별도 항목으로
        if (result.isNotEmpty && result.last.isNotEmpty) {
          result.add(''); // 이전 항목과 구분
        }
        result.add(trimmed);
        continue;
      }
      
      // 번호 패턴 확인 (1), 1., ①, 1) 등)
      final numberedPattern = RegExp(r'^(\d+)[\.\)]\s*|^[①②③④⑤⑥⑦⑧⑨⑩]\s*|^[가-힣][\.\)]\s*');
      if (numberedPattern.hasMatch(trimmed)) {
        // 번호가 있는 항목은 별도 항목으로
        if (result.isNotEmpty && result.last.isNotEmpty && !result.last.contains('\n')) {
          result.add(''); // 이전 항목과 구분
        }
        result.add(trimmed);
      } else {
        // 일반 텍스트는 이전 항목에 추가하거나 새 항목으로
        if (result.isEmpty || result.last.isEmpty) {
          result.add(trimmed);
        } else {
          // 이전 항목에 추가 (단락 유지)
          result[result.length - 1] = '${result.last}\n$trimmed';
        }
      }
    }
    
    // 최종 정리: 빈 항목 제거 및 마무리
    return result
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toList();
  }

  // DUR 라벨 매핑 포함한 Map → 라인
  List<String> _fromMap(Map m, {required bool isDur}) {
    final out = <String>[];

    // DUR 우선 키 라벨 매핑
    final durLabel = <String, String>{
      "typeName": "구분",
      "itemName": "품목명",
      "prohibitContent": "내용",
      "remark": "비고",
      "INGR_KOR_NAME": "성분",
      "MIXT_KOR_NAME": "혼합성분",
      "PROHBT_CONTENT": "내용",
      "REASON": "사유",
      "SEVERITY": "중증도",
      "AGE": "연령",
      "PREGNANT": "임부",
      "LACTATION": "수유",
      "TERM": "투여기간",
      "DOSAGE": "용량",
      "REMARK": "비고",
    };

    if (isDur) {
      // 1) 매핑 우선 출력
      for (final entry in durLabel.entries) {
        final v = m[entry.key] ?? m[entry.key.toLowerCase()];
        if (_isMeaningful(v)) {
          out.add("${entry.value}: ${v.toString().trim()}.");
        }
      }
    }

    // 2) 나머지 일반 키(코드/ID/seq/빈 구조/중복 제외)
    final skipKey = <String>{
      ...durLabel.keys.map((e) => e.toLowerCase()),
      "id",
      "code",
      "rnum",
      "seq",
    };

    m.forEach((key, val) {
      final ks = key.toString();
      final ksl = ks.toLowerCase();
      if (!_isMeaningful(val)) return;
      if (skipKey.any((s) => ksl.contains(s))) return;

      out.add("$ks: ${val.toString().trim()}.");
    });

    return out;
  }

  bool _isMeaningful(dynamic v) {
    if (v == null) return false;
    if (v is String) {
      final t = v.trim();
      return t.isNotEmpty && t != '{}' && t != '[]';
    }
    if (v is Iterable) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  List<String> _clean(List<String> xs) {
    return xs
        .map((e) => e.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((e) => e.isNotEmpty && e != '{}' && e != '[]')
        .toList();
  }

  // “라벨: 내용” 패턴을 가독형으로 보여주는 불릿 라인
  Widget bulletLine(String text) {
    // 빈 줄은 구분선으로 표시
    if (text.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(color: Colors.white12, height: 1),
      );
    }
    
    // 섹션 제목 패턴 확인 (효능효과, 용법용량, 사용상의주의사항 등)
    final sectionTitlePattern = RegExp(r'^(효능효과|용법용량|사용상의주의사항|주의사항|부작용|상호작용|임부|수유부|소아|고령자|과량|임상검사)');
    final isSectionTitle = sectionTitlePattern.hasMatch(text.trim());
    
    if (isSectionTitle) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 12),
        child: Text(
          text.trim(),
          style: TextStyle(
            color: const Color(0xFFFFEB3B),
            fontSize: 22,
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
        ),
      );
    }
    
    // 번호 패턴 확인 (1., 2., ①, 1) 등)
    final numberedPattern = RegExp(r'^(\d+)[\.\)]\s*|^[①②③④⑤⑥⑦⑧⑨⑩]\s*|^[가-힣][\.\)]\s*');
    final hasNumber = numberedPattern.hasMatch(text);
    
    // 라벨: 내용 패턴 확인
    final idx = text.indexOf(':');
    final hasLabel = idx > 0 && idx < text.length - 1 && !hasNumber;
    final label = hasLabel ? text.substring(0, idx).trim() : null;
    final rest = hasLabel ? text.substring(idx + 1).trim() : text.trim();
    
    // 줄바꿈이 있는 경우 처리
    final hasNewline = rest.contains('\n');
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 번호가 있으면 번호 스타일, 없으면 불릿
          if (hasNumber)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text(
                text.substring(0, numberedPattern.firstMatch(text)!.end),
                style: TextStyle(
                  color: const Color(0xFFFFEB3B),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 8, top: 2),
              child: Text("• ", style: TextStyle(color: Colors.white70, fontSize: 18)),
            ),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                children: [
                  if (label != null) 
                    TextSpan(text: "$label: ", style: _labelStyle),
                  TextSpan(
                    text: hasNewline 
                        ? rest 
                        : (rest.endsWith('.') || rest.endsWith('!') || rest.endsWith('?') 
                            ? rest 
                            : "$rest."),
                    style: _bodyStyle,
                  ),
                ],
              ),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      background: Colors.black,
      primary: Color(0xFFFFEB3B),
    );

    final list = _toReadableList(widget.title, widget.contents);

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: list.isEmpty
            ? const Text(
                "표시할 내용이 없습니다.",
                style: TextStyle(color: Colors.white70, fontSize: 18),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) {
                  // 빈 줄은 구분선으로, 일반 텍스트는 bulletLine으로
                  return bulletLine(list[index]);
                },
              ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// (선택) 문단 프리뷰 위젯: 긴 텍스트 4줄까지만 → 더보기/접기
class ReadableParagraph extends StatefulWidget {
  final String text;
  const ReadableParagraph({super.key, required this.text});

  @override
  State<ReadableParagraph> createState() => _ReadableParagraphState();
}

class _ReadableParagraphState extends State<ReadableParagraph> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    final child = SelectableText(
      text,
      style: _bodyStyle,
      textAlign: TextAlign.start,
    );

    return Semantics(
      label: "본문",
      hint: _expanded ? "접기 버튼으로 닫기" : "더보기 버튼으로 펼치기",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 150),
            firstChild: _Clamped(child: child, maxLines: 4),
            secondChild: child,
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? "접기" : "더보기", style: _mutedStyle),
          ),
        ],
      ),
    );
  }
}

class _Clamped extends StatelessWidget {
  final Widget child;
  final int maxLines;
  const _Clamped({required this.child, required this.maxLines});

  @override
  Widget build(BuildContext context) {
    if (child is SelectableText) {
      final t = (child as SelectableText);
      return SelectableText(
        t.data ?? "",
        style: t.style,
        maxLines: maxLines,
      );
    }
    return child;
  }
}