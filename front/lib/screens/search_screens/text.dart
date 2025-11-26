// front/lib/screens/search_screens/text.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../details/drug_detail.dart';
import '/api_services/api_helper.dart';
import '/services/theme_service.dart';
import '/widgets/accessible_scaffold.dart';
import '/widgets/accessible_button.dart';

class TextSearchScreen extends StatefulWidget {
  const TextSearchScreen({super.key});
  @override
  State<TextSearchScreen> createState() => _TextSearchScreenState();
}

class _TextSearchScreenState extends State<TextSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FlutterTts tts = FlutterTts();
  final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  List<dynamic>? _items;
  bool _isLoading = false;

  DateTime? _lastTap; // 디바운스용

  // ⬇️ 추가: 요청 취소/워치독/키워드칩
  CancelToken? _inflight;
  Timer? _watchdog;
  List<String> _lastKeywords = const [];

  @override
  void initState() {
    super.initState();
    _initVoiceGuide();
  }

  Future<void> _initVoiceGuide() async {
    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      await tts.setLanguage("ko-KR");
      await tts.setSpeechRate(0.45);
      await tts.speak("텍스트 검색입니다. 의약품명은 2자 이상, 공백 또는 쉼표로 구분해 입력한 뒤, 검색을 누르세요.");
    }
  }

  Future<void> _speak(String text) async {
    final theme = context.read<ThemeService>();
    if (!theme.isVoiceGuideEnabled) return;
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
    await tts.stop();
    await tts.speak(text);
  }

  // 입력 파싱: 공백/쉼표, 2자 미만 제거, 중복 제거
  List<String> _parseKeywords(String raw) => raw
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim())
      .where((e) => e.length >= 2)
      .toSet()
      .toList();

  String _buildBaseUrl() {
    // .env 로드 누락 대비 안전장치 + 트레일링 슬래시 제거
    final fromEnv = dotenv.maybeGet('API_BASE_URL')?.trim() ?? '';
    final base = fromEnv.isEmpty ? '' : (fromEnv.endsWith('/') ? fromEnv.substring(0, fromEnv.length - 1) : fromEnv);
    return base;
  }

  Future<void> _searchDrug() async {
    // 디바운스
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 600)) return;
    _lastTap = now;

    final raw = _controller.text;
    final keywords = _parseKeywords(raw);
    if (keywords.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("2자 이상으로 입력하세요 (공백/쉼표 구분)"), backgroundColor: Colors.red[700]),
        );
      }
      await _speak("2자 이상으로 의약품명을 입력해주세요. 공백이나 쉼표로 여러 개를 구분할 수 있습니다.");
      return;
    }

    final baseUrl = _buildBaseUrl();
    if (baseUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("API_BASE_URL이 설정되지 않았어요 (.env 확인)"), backgroundColor: Colors.red[800]),
        );
      }
      await _speak("서버 주소가 설정되지 않았습니다. 개발자 설정을 확인해주세요.");
      return;
    }

    // 진행 중 요청이 있으면 취소
    _inflight?.cancel("새 검색으로 이전 요청 취소");
    _watchdog?.cancel();

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _items = null;
      _lastKeywords = List<String>.from(keywords);
    });

    // 로딩 즉시 피드백
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("검색 중…"), backgroundColor: Colors.black87, duration: Duration(seconds: 1)),
      );
    }
    await Vibration.vibrate(duration: 50);
    await _speak("검색을 시작합니다.");

    _inflight = CancelToken();

    // 워치독 제거 - 타임아웃 예외 처리로 충분함
    // 실제 타임아웃은 10초로 설정되어 있고, 워치독이 먼저 실행되면 잘못된 메시지가 표시됨

    try {
      // 백엔드 라우터가 prefix 없이 등록되어 있어서 /keyword-search로 직접 접근
      final url = "$baseUrl/keyword-search";
      final headers = await ApiHelper.getAuthHeaders(); // {Authorization: Bearer ...}

      // 백엔드 사양: keyword=단일 문자열 (쉼표로 합침)
      final joined = keywords.join(',');
      final resp = await dio
          .get(
            url,
            queryParameters: {"keyword": joined},
            options: Options(
              headers: {
                "accept": "application/json",
                ...headers,
              },
            ),
            cancelToken: _inflight,
          )
          .timeout(const Duration(seconds: 10)); // 수동 타임아웃

      final data = resp.data;
      final items = data["results"]?["items"] ?? data["items"] ?? [];

      if (!mounted) return;
      setState(() {
        _items = List<dynamic>.from(items);
      });

      if (_items!.isEmpty) {
        await _speak("검색 결과가 없습니다. 다른 키워드로 시도해주세요.");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("검색 결과 없음"), backgroundColor: Colors.grey[850]),
        );
      } else {
        await Vibration.vibrate(duration: 90);
        final firstNames = _items!
            .take(3)
            .map((e) => (e["itemName"] ?? "").toString())
            .where((s) => s.isNotEmpty)
            .join(", ");
        await _speak("결과가 ${_items!.length}건 있습니다. 예: $firstNames. 목록에서 항목을 탭하면 상세로 이동합니다.");
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text("요청이 시간초과되었습니다 (10초)."), backgroundColor: Colors.red[700]),
      );
      await _speak("요청이 시간초과되었습니다. 네트워크 상태를 확인 후 다시 시도해주세요.");
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = e.type == DioExceptionType.cancel
          ? "요청이 취소되었습니다."
          : "요청 실패: ${e.message}";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
      );
      if (e.type != DioExceptionType.cancel) {
        await _speak("약 정보를 불러오지 못했습니다. 네트워크 상태를 확인한 후 다시 시도해주세요.");
      }
    } catch (e, st) {
      if (!mounted) return;
      // ignore: avoid_print
      print("❌ TextSearch error: $e\n$st");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("에러: $e"), backgroundColor: Colors.red[700]),
      );
      await _speak("예기치 못한 오류가 발생했습니다.");
    } finally {
      // 워치독 제거됨
      if (mounted) {
        setState(() => _isLoading = false); // 무조건 내려주기
      }
    }
  }

  Future<void> _openDrugDetail(dynamic item) async {
    final name = item["itemName"] ?? "이름 정보 없음";
    await _speak("$name 상세 정보를 열겠습니다.");
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DrugDetailScreen(initialDrugInfo: item)),
    );
    if (!mounted) return;
    await _speak("다른 약을 검색하려면 입력 후 검색을 누르세요.");
  }

  /// 이미지 크롤링 API 호출
  Future<String?> _fetchImageFromScraper(String itemSeq) async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    if (baseUrl.isEmpty || itemSeq.isEmpty) return null;

    try {
      final uri = Uri.parse('$baseUrl/image-scrape?item_seq=$itemSeq');
      final headers = await ApiHelper.getAuthHeaders();

      debugPrint('📸 [text-search] image-scrape GET $uri');

      final resp = await http.get(uri, headers: headers);
      debugPrint('📸 [text-search] image-scrape status = ${resp.statusCode}');

      if (resp.statusCode != 200) {
        return null;
      }

      // 서버가 이미지 바이너리를 직접 내려주는 경우, 엔드포인트 URL을 이미지 URL로 사용
      final contentType =
          resp.headers['content-type'] ?? resp.headers['Content-Type'] ?? '';
      if (contentType.startsWith('image/')) {
        final url = uri.toString();
        debugPrint('📸 [text-search] using endpoint as image url = $url');
        return url;
      }

      return null;
    } catch (e) {
      debugPrint('📸 [text-search] image-scrape error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    tts.stop();
    _controller.dispose();
    _inflight?.cancel("스크린 dispose");
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: "텍스트로 약 검색",
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Semantics(
                    textField: true,
                    label: "의약품명 입력",
                    hint: "2자 이상, 공백 또는 쉼표로 구분하여 입력하세요",
                    child: TextField(
                      controller: _controller,
                      style: theme.bodyTextStyle,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        if (!_isLoading) _searchDrug();
                      },
                      decoration: InputDecoration(
                        labelText: '의약품명 (2자 이상, 공백/쉼표 구분)',
                        hintText: '예) 타이레놀 500, 아세트아미노펜',
                        labelStyle: theme.subtitleTextStyle,
                        hintStyle: theme.subtitleTextStyle,
                        suffixIcon: Semantics(
                          button: true,
                          label: "입력 지우기",
                          child: IconButton(
                            tooltip: "입력 지우기",
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _items = null;
                                _lastKeywords = const [];
                              });
                            },
                            icon: Icon(Icons.clear, color: theme.textColor.withOpacity(0.7)),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.primaryColor)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: theme.primaryColor, width: 2)),
                        filled: true,
                        fillColor: theme.backgroundColor.withOpacity(0.1),
                      ),
                      onTap: () async {
                        if (theme.isVoiceGuideEnabled) {
                          await _speak("의약품명을 입력하세요. 2자 이상, 공백이나 쉼표로 구분할 수 있습니다.");
                        }
                      },
                    ),
                  ),

                  // ⬇️ 최근 검색 키워드 Chip으로 명확히 표시 (이름 검색이 위에 보이는 문제 완화)
                  if (_lastKeywords.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _lastKeywords
                            .map((k) => Semantics(
                                  button: true,
                                  label: "$k 키워드 삭제",
                                  child: Chip(
                                    label: Text(k, style: theme.subtitleTextStyle.copyWith(color: theme.buttonTextColor)),
                                    backgroundColor: theme.primaryColor,
                                    deleteIcon: Icon(Icons.close, size: 16, color: theme.buttonTextColor),
                                    onDeleted: () {
                                      final next = List<String>.from(_lastKeywords)..remove(k);
                                      setState(() => _lastKeywords = next);
                                      _controller.text = next.join(', ');
                                    },
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  AccessibleButton(
                    label: "검색하기",
                    icon: Icons.search,
                    hint: "입력한 의약품명으로 검색합니다",
                    onPressed: _isLoading ? () {} : _searchDrug,
                    height: 56,
                    textStyle: theme.buttonTextStyle.copyWith(
                      fontSize: 20 * theme.fontScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 로딩 표시
                  if (_isLoading) ...[
                    CircularProgressIndicator(color: theme.primaryColor),
                    const SizedBox(height: 12),
                    Text('검색 중…', style: theme.bodyTextStyle),
                  ],

              // 결과 리스트
              if (!_isLoading && _items != null) ...[
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: _items!.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _items![index];
                      return _DrugListItem(
                        drug: item,
                        onTap: () => _openDrugDetail(item),
                        fetchImage: _fetchImageFromScraper,
                      );
                    },
                  ),
                ),
              ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 검색 결과 아이템 위젯 (이미지 크롤링 지원)
class _DrugListItem extends StatefulWidget {
  final Map<String, dynamic> drug;
  final VoidCallback onTap;
  final Future<String?> Function(String) fetchImage;

  const _DrugListItem({
    required this.drug,
    required this.onTap,
    required this.fetchImage,
  });

  @override
  State<_DrugListItem> createState() => _DrugListItemState();
}

class _DrugListItemState extends State<_DrugListItem> {
  String? _imageUrl;
  bool _isLoadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final itemSeq = (widget.drug['itemSeq'] ?? 
                    widget.drug['item_seq'] ?? 
                    "").toString();

    // 이미지 URL 여러 필드 확인
    String imageUrl = (widget.drug['imageUrl'] ?? 
                     widget.drug['itemImage'] ?? 
                     widget.drug['image'] ?? 
                     widget.drug['ITEM_IMAGE'] ??
                     widget.drug['thumbnail'] ?? 
                     "").toString();
    
    // 이미지가 없고 itemSeq가 있으면 크롤링 시도
    if ((imageUrl.isEmpty || imageUrl == "null") && itemSeq.isNotEmpty) {
      if (mounted) {
        setState(() => _isLoadingImage = true);
      }
      try {
        final scrapedUrl = await widget.fetchImage(itemSeq);
        if (scrapedUrl != null && scrapedUrl.isNotEmpty) {
          imageUrl = scrapedUrl;
        }
      } catch (e) {
        debugPrint('📸 [text-search] 이미지 크롤링 실패: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoadingImage = false);
        }
      }
    }

    if (mounted && imageUrl.isNotEmpty && imageUrl != "null") {
      setState(() => _imageUrl = imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.drug['itemName'] ?? '이름없음';
    final company = widget.drug['entpName'] ?? '';

    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return Semantics(
          button: true,
          label: "$name, 제조사: $company",
          hint: "탭하여 상세 정보를 확인합니다",
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.backgroundColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.primaryColor, width: 1.2),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _isLoadingImage
                        ? Container(
                            width: 56,
                            height: 56,
                            color: theme.backgroundColor.withOpacity(0.2),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                          )
                        : (_imageUrl != null && _imageUrl!.isNotEmpty)
                            ? Image.network(
                                _imageUrl!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 56,
                                  height: 56,
                                  color: theme.backgroundColor.withOpacity(0.2),
                                  child: Icon(
                                    Icons.medication_outlined,
                                    color: theme.textColor.withOpacity(0.7),
                                    size: 28,
                                  ),
                                ),
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 56,
                                    height: 56,
                                    color: theme.backgroundColor.withOpacity(0.2),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                        color: theme.primaryColor,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                color: theme.backgroundColor.withOpacity(0.2),
                                child: Icon(
                                  Icons.medication_outlined,
                                  color: theme.textColor.withOpacity(0.7),
                                  size: 28,
                                ),
                              ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(text: '이름: ', style: theme.subtitleTextStyle.copyWith(fontWeight: FontWeight.w700)),
                            TextSpan(text: name, style: theme.bodyTextStyle.copyWith(fontWeight: FontWeight.w600)),
                          ]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(text: '제조사: ', style: theme.subtitleTextStyle.copyWith(fontWeight: FontWeight.w700)),
                            TextSpan(text: company, style: theme.subtitleTextStyle),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
}