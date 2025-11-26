// front/lib/screens/search_screens/voice.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'; // SemanticsService.announce
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '/api_services/api_helper.dart';
import '/services/theme_service.dart';
import '/widgets/accessible_scaffold.dart';
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

  bool _announced = false; // 첫 진입 안내 중복 방지
  String _bufferedInput = "";

  List<Map<String, dynamic>> searchResults = [];
  String? currentKeyword;

  @override
  void initState() {
    super.initState();
    _prepareTTS();
  }

  Future<void> _prepareTTS() async {
    await tts.setLanguage("ko-KR");
    await tts.setSpeechRate(0.45);
  }

  /// 첫 진입 시 단 한 번만 안내.
  /// - 앱 음성안내 ON: TTS 사용 (Talkback 여부와 관계없이)
  /// - Talkback 사용자도 TTS 사용 가능 (중복이어도 괜찮음)
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    _announced = true;

    final theme = context.read<ThemeService>();

    Future.delayed(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      const msg = "검색하시려면 중앙 마이크 버튼을 꾹 누른 상태로 말씀해주세요.";

      // 음성 안내가 켜져있으면 TTS 사용 (Talkback 여부와 관계없이)
      if (theme.isVoiceGuideEnabled) {
        await _speak(msg);
      }
    });
  }

  @override
  void dispose() {
    tts.stop();
    sttInstance.stop();
    super.dispose();
  }

  Future<void> _speak(String text, {bool listenAfter = false}) async {
    final theme = context.read<ThemeService>();

    // 음성 안내가 꺼져있으면 TTS 사용 안 함
    if (!theme.isVoiceGuideEnabled) {
      if (listenAfter) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _startHoldListen();
      }
      return;
    }

    await tts.stop();
    
    // TTS 완료를 기다리는 Completer 사용
    final completer = Completer<void>();
    tts.setCompletionHandler(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    
    await tts.speak(text);
    
    // TTS 완료 대기
    await completer.future;
    
    if (listenAfter) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 300));
      await Vibration.vibrate(duration: 80);
      await _startHoldListen();
    }
  }

  // ─────────────────────────────────────────────
  // 🎤 녹음 제어 (일반 모드: 길게 누르기)
  // ─────────────────────────────────────────────
  Future<void> _startHoldListen() async {
    if (isListening || isBusy) return;

    setState(() {
      isListening = true;
      _bufferedInput = "";
    });

    final available = await sttInstance.initialize(
      onStatus: (status) => debugPrint("🎤 STT status: $status"),
      onError: (err) => debugPrint("❌ STT error: $err"),
    );

    if (available) {
      await Vibration.vibrate(duration: 40);
      await sttInstance.listen(
        localeId: "ko_KR",
        listenMode: stt.ListenMode.dictation,
        onResult: (result) {
          debugPrint("🎤 STT result: ${result.recognizedWords}, finalResult: ${result.finalResult}");
          if (result.finalResult) {
            _bufferedInput = result.recognizedWords.trim();
            debugPrint("✅ 최종 인식 결과: $_bufferedInput");
          } else {
            // 중간 결과도 버퍼에 저장 (실시간 피드백)
            _bufferedInput = result.recognizedWords.trim();
          }
        },
      );
    } else {
      if (!mounted) return;
      setState(() => isListening = false);
      await _speak("음성 인식을 시작할 수 없습니다.");
    }
  }

  Future<void> _endHoldListen() async {
    if (!isListening) return;
    await sttInstance.stop();
    await Vibration.vibrate(duration: 60);

    // 잠시 대기하여 STT가 최종 결과를 처리할 시간 제공
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;
    setState(() {
      isListening = false;
      isBusy = true;
    });

    final input = _bufferedInput;
    debugPrint("🔍 처리할 입력: '$input'");
    _bufferedInput = "";

    await _processBufferedInput(input);
  }

  // ─────────────────────────────────────────────
  // 🟠 TalkBack 모드: 더블탭(=onTap)으로 토글
  // ─────────────────────────────────────────────
  Future<void> _tapToggleListen() async {
    if (isBusy) return;

    // 시작
    if (!isListening) {
      final available = await sttInstance.initialize(
        onStatus: (status) => debugPrint("🎤 STT status: $status"),
        onError: (err) => debugPrint("❌ STT error: $err"),
      );

      if (available) {
        if (!mounted) return;
        setState(() {
          isListening = true;
          _bufferedInput = "";
        });
        await Vibration.vibrate(duration: 40);
        await sttInstance.listen(
          localeId: "ko_KR",
          listenMode: stt.ListenMode.dictation,
          onResult: (result) {
            debugPrint("🎤 STT result: ${result.recognizedWords}, finalResult: ${result.finalResult}");
            if (result.finalResult) {
              _bufferedInput = result.recognizedWords.trim();
              debugPrint("✅ 최종 인식 결과: $_bufferedInput");
            } else {
              // 중간 결과도 버퍼에 저장 (실시간 피드백)
              _bufferedInput = result.recognizedWords.trim();
            }
          },
        );
        SemanticsService.announce("듣기 시작", TextDirection.ltr);
      } else {
        await _speak("음성 인식을 시작할 수 없습니다.");
      }
      return;
    }

    // 종료 + 처리
    await sttInstance.stop();
    await Vibration.vibrate(duration: 60);

    // 잠시 대기하여 STT가 최종 결과를 처리할 시간 제공
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;
    setState(() {
      isListening = false;
      isBusy = true;
    });

    final input = _bufferedInput;
    debugPrint("🔍 처리할 입력: '$input'");
    _bufferedInput = "";

    await _processBufferedInput(input);
    SemanticsService.announce("전송 완료", TextDirection.ltr);
  }

  // 공통 처리
  Future<void> _processBufferedInput(String input) async {
    if (input.isEmpty) {
      await _speak("음성이 인식되지 않았습니다. 다시 말씀해주세요.");
      if (!mounted) return;
      setState(() => isBusy = false);
      return;
    }

    // ✅ 선택 단계였는데 목록이 비었으면 검색 단계로 전환
  if (currentKeyword != null && searchResults.isEmpty) {
    currentKeyword = null;
  }

  if (currentKeyword == null) {
    currentKeyword = input;
    await _searchDrug(input);
  } else {
    await _selectDrug(input);
  }

  if (!mounted) return;
  setState(() => isBusy = false);
  }

  // ─────────────────────────────────────────────
  // 🔎 검색 & 선택
  // ─────────────────────────────────────────────
  Future<void> _searchDrug(String keyword) async {
    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    final cleanedKeyword = keyword.replaceAll(" ", "");

    // ✅ TTS가 프레임을 막지 않도록 '대기하지 말고' 비동기로만 호출
    Future.microtask(() => _speak("$keyword 약을 검색합니다."));

    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      // 백엔드 라우터가 prefix 없이 등록되어 있어서 /keyword-search로 직접 접근
      final url = "$baseUrl/keyword-search";
      final headers = await ApiHelper.getAuthHeaders();

      final response = await dio.get(
        url,
        queryParameters: {"keyword": cleanedKeyword},
        options: Options(headers: headers),
      );

      if (!mounted) return; // ✅ 안전 가드

      if (response.statusCode == 200) {
        final data = response.data;
        final items =
            List<Map<String, dynamic>>.from(data["results"]["items"] ?? []);
        if (items.isEmpty) {
          await _speak("검색 결과가 없습니다. 다시 말씀해주세요.");
          currentKeyword = null;
          return;
        }

        searchResults = items;
        final names = items
            .map((e) => (e["itemName"] as String? ?? "이름없음")
                .replaceAll(RegExp(r'\(.*?\)'), ''))
            .join(", ");

        // 결과를 말로 안내 (비동기로)
        Future.microtask(
            () => _speak("검색 결과입니다. $names 중 어떤 약을 선택하시겠습니까?"));

        // 팝업은 한 틱 뒤에
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _showSearchResultsPopup(items);
        });
      } else {
        await _speak("서버 응답이 올바르지 않습니다. 다시 시도해주세요.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "검색 중 오류가 발생했습니다: ${e.toString()}";
      });
      await _speak("검색 중 오류가 발생했습니다. 네트워크를 확인해주세요.");
    } finally {
      if (!mounted) return; // ✅ 안전 가드
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _showSearchResultsPopup(List<Map<String, dynamic>> items) async {
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer<ThemeService>(
          builder: (context, theme, child) {
            return Container(
              decoration: BoxDecoration(
                color: theme.backgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 제목
                      Text(
                        "검색 결과",
                        style: theme.titleStyle.copyWith(
                          fontSize: 24 * theme.fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 리스트
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final drug = items[index];
                            return _DrugListItem(
                              drug: drug,
                              onTap: () async {
                                Navigator.pop(context);
                                await _onDrugSelected(drug);
                              },
                              fetchImage: _fetchImageFromScraper,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
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
      await _speak("일치하는 약을 찾을 수 없습니다. 다시 말씀해주세요.");
    }
  }

  Future<void> _onDrugSelected(Map<String, dynamic> drug) async {
    final rawName = (drug["itemName"] ?? "이름없음").toString();
    final name = rawName.replaceAll(RegExp(r'\(.*?\)'), '');
    Future.microtask(() => _speak("$name 약을 선택했습니다."));
    Vibration.vibrate(duration: 200);

    if (!mounted) return;
    // ✅ 상세로 이동을 기다렸다가
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrugDetailScreen(initialDrugInfo: drug),
      ),
    );

    // ✅ 돌아오면 검색 상태 초기화
    if (!mounted) return;
    setState(() {
      currentKeyword = null;
      searchResults = [];
      isBusy = false;
      _isSearching = false;
      _errorMessage = null;
    });

    // 안내 문구 한 줄 (선택)
    Future.microtask(() => _speak("다른 약을 검색하시려면 마이크 버튼을 길게 눌러주세요."));
  }

  /// 이미지 크롤링 API 호출
  Future<String?> _fetchImageFromScraper(String itemSeq) async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    if (baseUrl.isEmpty || itemSeq.isEmpty) return null;

    try {
      final uri = Uri.parse('$baseUrl/image-scrape?item_seq=$itemSeq');
      final headers = await ApiHelper.getAuthHeaders();

      debugPrint('📸 [voice-search] image-scrape GET $uri');

      final resp = await http.get(uri, headers: headers);
      debugPrint('📸 [voice-search] image-scrape status = ${resp.statusCode}');

      if (resp.statusCode != 200) {
        return null;
      }

      // 서버가 이미지 바이너리를 직접 내려주는 경우, 엔드포인트 URL을 이미지 URL로 사용
      final contentType =
          resp.headers['content-type'] ?? resp.headers['Content-Type'] ?? '';
      if (contentType.startsWith('image/')) {
        final url = uri.toString();
        debugPrint('📸 [voice-search] using endpoint as image url = $url');
        return url;
      }

      return null;
    } catch (e) {
      debugPrint('📸 [voice-search] image-scrape error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a11y =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final bool isScreenReaderLike = a11y.accessibleNavigation;

    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '음성 검색',
          body: _isSearching
              // ✅ (1) 로딩 뷰: 인디케이터 명도/두께 고정 + 텍스트 검은색
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        const CircularProgressIndicator(
                          strokeWidth: 4, // 두껍게
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.deepOrange, // 눈에 띄는 주황
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "검색중입니다...",
                          style: TextStyle(
                            fontSize: 18 * theme.fontScale,
                            fontWeight: FontWeight.w700,
                            color: Colors.black, // 검은색 고정
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _errorMessage != null
                  ? _ErrorBox(
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
                            // ✅ 상단 고정 안내문 (중복 안내 제거됨)
                            Semantics(
                              label: "안내",
                              hint:
                                  "검색하시려면 중앙 마이크 버튼을 꾹 누른 상태로 말씀해주세요.",
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  "검색하시려면 중앙 마이크 버튼을 꾹 누른 상태로 말씀해주세요",
                                  textAlign: TextAlign.center,
                                  style: theme.bodyTextStyle.copyWith(
                                    fontSize: 16 * theme.fontScale,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),

                            // 🎤 큰 원형 마이크 버튼
                            Semantics(
                              button: true,
                              label: "음성 입력 버튼",
                              hint: isScreenReaderLike
                                  ? "더블탭하면 듣기가 시작 또는 종료됩니다."
                                  : "길게 누르면 듣기가 시작되고, 손을 떼면 전송됩니다.",
                              child: GestureDetector(
                                onTap: isScreenReaderLike
                                    ? () => _tapToggleListen()
                                    : null,
                                onLongPressStart: isScreenReaderLike
                                    ? null
                                    : (_) => _startHoldListen(),
                                onLongPressEnd: isScreenReaderLike
                                    ? null
                                    : (_) => _endHoldListen(),
                                child: AnimatedScale(
                                  duration:
                                      const Duration(milliseconds: 140),
                                  scale: isListening ? 1.08 : 1.0,
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 160),
                                    height: 120 * theme.fontScale,
                                    width: 120 * theme.fontScale,
                                    decoration: BoxDecoration(
                                      color: isListening
                                          ? Colors.deepOrangeAccent
                                          : theme.primaryColor,
                                      shape: BoxShape.circle,
                                      boxShadow: isListening
                                          ? [
                                              BoxShadow(
                                                blurRadius: 20,
                                                spreadRadius: 8,
                                                color:
                                                    Colors.deepOrangeAccent
                                                        .withOpacity(0.5),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Icon(
                                      isListening
                                          ? Icons.mic
                                          : Icons.mic_none,
                                      size: 56 * theme.fontScale,
                                      color: theme.buttonTextColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // 상태 텍스트
                            if (isListening || isBusy)
                              Text(
                                isListening ? "듣는 중…" : "처리 중…",
                                style: theme.bodyTextStyle.copyWith(
                                  fontSize: 16 * theme.fontScale,
                                  color: isListening
                                      ? Colors.green
                                      : Colors.orange,
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
    final itemSeq = (widget.drug["itemSeq"] ?? 
                    widget.drug["item_seq"] ?? 
                    "").toString();

    // 이미지 URL 여러 필드 확인
    String imageUrl = (widget.drug["imageUrl"] ?? 
                     widget.drug["itemImage"] ?? 
                     widget.drug["image"] ?? 
                     widget.drug["ITEM_IMAGE"] ??
                     widget.drug["thumbnail"] ?? 
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
        debugPrint('📸 [voice-search] 이미지 크롤링 실패: $e');
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
    final rawName = (widget.drug["itemName"] ?? "이름없음").toString();
    final name = rawName.replaceAll(RegExp(r'\(.*?\)'), '');
    final company = (widget.drug["entpName"] ?? "").toString();

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
                border: Border.all(
                  color: theme.primaryColor,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  // 이미지
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
                  // 텍스트 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '이름: ',
                                style: theme.subtitleTextStyle.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: name,
                                style: theme.bodyTextStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '제조사: ',
                                style: theme.subtitleTextStyle.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: company,
                                style: theme.subtitleTextStyle,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.textColor.withOpacity(0.5),
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

/// 간단 에러 박스 (검은 텍스트로 보이게)
class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (_, theme, __) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 40, color: Colors.red[400]),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16 * theme.fontScale,
                    color: Colors.black, // 검은색 고정
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    "다시 시도",
                    style: TextStyle(
                      fontSize: 16 * theme.fontScale,
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}