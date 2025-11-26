// lib/screens/upload_page_screens/prescription_result.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:pillypilly_h/api_services/api_helper.dart';
import '../../services/prescription_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import '../../widgets/loading_widget.dart';
import '../details/drug_detail.dart';
import 'pill_capture.dart';

class PrescriptionResultPage extends StatefulWidget {
  final String prescriptionId;
  final int totalCount;
  final List<dynamic>? initialResults; // 분석 응답에서 받은 초기 결과
  final bool pillsCaptured; // 알약 촬영 완료 여부

  const PrescriptionResultPage({
    Key? key,
    required this.prescriptionId,
    required this.totalCount,
    this.initialResults,
    this.pillsCaptured = false, // 기본값은 false
  }) : super(key: key);

  @override
  State<PrescriptionResultPage> createState() => _PrescriptionResultPageState();
}

class _PrescriptionResultPageState extends State<PrescriptionResultPage> {
  final Dio _dio = Dio();
  final PrescriptionService _prescriptionService = PrescriptionService();
  final FlutterTts _tts = FlutterTts();

  bool _loading = true;
  bool _error = false;
  List<dynamic> _items = [];
  List<String> _sequenceText = [];
  bool _hasAnnounced = false; // 초기 안내 음성 재생 여부
  bool _isSaved = false; // 저장 여부 추적
  int _pollingAttempts = 0; // 폴링 시도 횟수
  static const int _maxPollingAttempts = 10; // 최대 폴링 시도 횟수

  @override
  void initState() {
    super.initState();
    
    // 초기 결과가 있으면 먼저 표시
    if (widget.initialResults != null && widget.initialResults!.isNotEmpty) {
      setState(() {
        _items = widget.initialResults!;
        _loading = false;
      });
      // 초기 결과 안내 음성 재생
      Future.microtask(() async {
        if (!_hasAnnounced && _items.isNotEmpty) {
          _hasAnnounced = true;
          final itemCount = _items.length;
          await _announce(
            "처방전 분석 결과입니다. 총 $itemCount개의 약이 인식되었습니다. "
            "각 약을 탭하면 상세 정보를 확인할 수 있습니다.",
          );
          await Vibration.vibrate(duration: 200);
        }
      });
    }
    
    // 약 5초 대기 후 결과 조회 (백엔드 비동기 처리 시간 확보)
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _fetchResult();
      }
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _announce(String text) async {
    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
    }
  }

  String _cleanBase(String raw) {
    if (raw.isEmpty) return raw;
    final t = raw.trim();
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  Future<void> _fetchResult() async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    if (baseUrl.isEmpty) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = false;
    });

    try {
      /// ④ 결과 조회 → /api/v3/prescriptions/{prescription_id}/results
      final url =
          '${_cleanBase(baseUrl)}/api/v3/prescriptions/${widget.prescriptionId}/results';

      final headers = await ApiHelper.getAuthHeaders();

      debugPrint("📤 [REQUEST] GET $url");
      debugPrint("📤 [REQUEST HEADERS] $headers");

      final res = await _dio.get(
        url,
        options: Options(headers: headers),
      );

      debugPrint("📥 [RESPONSE STATUS] ${res.statusCode}");
      debugPrint("📥 [RESPONSE DATA] ${res.data}");

      if (!mounted) return;

      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        final status = data['status']?.toString().toUpperCase();
        final results = (data['results'] as List?) ?? [];
        final guide = (data['guide'] as Map?) ?? {};
        final seqListRaw = guide['sequence_text'] as List?;
        final seqList = seqListRaw != null
            ? seqListRaw.map((e) => e.toString()).toList()
            : <String>[];

        // 결과가 있고 status가 COMPLETED이거나, results가 비어있지 않으면 업데이트
        if (results.isNotEmpty) {
          // 백엔드에서 결과가 있으면 업데이트
          // 백엔드 응답 구조 확인: selected 객체 안에 있을 수도 있음
          final processedResults = results.map((item) {
            if (item is Map) {
              final selected = item['selected'] as Map?;
              // selected가 있으면 그대로 사용, 없으면 item 자체 사용
              return selected ?? item;
            }
            return item;
          }).toList();
          
          setState(() {
            _items = processedResults;
            _sequenceText = seqList;
            _loading = false;
          });

          // 결과 안내 음성 재생 (아직 안내하지 않았고 결과가 있을 때만)
          if (!_hasAnnounced && _items.isNotEmpty) {
            _hasAnnounced = true;
            final itemCount = _items.length;
            await _announce(
              "처방전 분석 결과입니다. 총 $itemCount개의 약이 인식되었습니다. "
              "각 약을 탭하면 상세 정보를 확인할 수 있습니다.",
            );
            await Vibration.vibrate(duration: 200);
          }
        } else if (status == 'COMPLETED') {
          // 처리 완료되었지만 결과가 없으면 로딩 종료
          setState(() {
            _loading = false;
          });
        } else if (status == 'PROCESSING') {
          // 처리 중인데 결과가 없음
          if (_items.isNotEmpty) {
            // 이미 화면에 결과가 있으면 기존 결과 유지하고 폴링 중단
            debugPrint("✅ [처방전 결과] 이미 결과가 표시되어 있습니다. 기존 결과를 유지합니다.");
            setState(() {
              _loading = false;
            });
          } else if (_pollingAttempts < _maxPollingAttempts) {
            // 화면에 결과가 없으면 폴링 재시도
            _pollingAttempts++;
            debugPrint("⏳ [처방전 결과] 아직 처리 중입니다. 3초 후 다시 시도합니다. (시도: $_pollingAttempts/$_maxPollingAttempts)");
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) {
              _fetchResult();
            }
            return;
          } else {
            // 최대 시도 횟수 초과
            debugPrint("⏸️ [처방전 결과] 최대 폴링 시도 횟수에 도달했습니다.");
            setState(() {
              _loading = false;
            });
          }
        } else {
          // 결과가 없고 처리도 완료되지 않았으면 로딩 종료
          setState(() {
            _loading = false;
          });
        }

        // 자동 저장 다이얼로그는 제거 - 끝내기 버튼으로 저장 여부 선택
      } else {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final responseData = e.response?.data;
      
      debugPrint("❌ [FETCH ERROR] Status: $code");
      debugPrint("❌ [RESPONSE DATA] $responseData");
      
      if (!mounted) return;
      
      String errorMsg = "결과를 불러오는 데 실패했습니다.";
      if (code == 502) {
        // 502 Bad Gateway: 외부 API 호출 실패
        final msg = responseData is Map 
            ? (responseData['error']?['message'] ?? responseData['message'] ?? '외부 서비스 연결 실패')
            : '서버가 외부 서비스에 연결할 수 없습니다';
        errorMsg = "서버 연결 오류: $msg";
      } else if (code == 500) {
        errorMsg = "서버 내부 오류가 발생했습니다";
      } else if (code == 503) {
        errorMsg = "서버가 일시적으로 사용할 수 없습니다";
      }
      
      setState(() {
        _loading = false;
        _error = true;
      });
      
      final theme = context.read<ThemeService>();
      if (theme.isVoiceGuideEnabled) {
        await _announce(errorMsg);
      }
    } catch (e, stack) {
      debugPrint("❌ [FETCH ERROR] $e");
      debugPrint("❌ [STACKTRACE]\n$stack");
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
      
      final theme = context.read<ThemeService>();
      if (theme.isVoiceGuideEnabled) {
        await _announce("결과를 불러오는 중 오류가 발생했습니다.");
      }
    }
  }

  /// 끝내기 버튼 클릭 시 저장 여부 묻는 다이얼로그
  Future<void> _showExitDialog() async {
    if (!mounted) return;

    final theme = context.read<ThemeService>();
    
    // 이미 저장된 경우 바로 홈화면으로 이동
    if (_isSaved) {
      if (theme.isVoiceGuideEnabled) {
        await _announce("처방전 분석 결과 화면을 종료하고 홈화면으로 돌아갑니다.");
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return AlertDialog(
            backgroundColor: theme.backgroundColor,
            title: Text(
              '처방전 저장',
              style: theme.titleStyle.copyWith(fontSize: 24 * theme.fontScale),
            ),
            content: Text(
              '이 처방전을 보관함에 저장하시겠습니까?\n나중에 기록함에서 다시 불러올 수 있습니다.',
              style: theme.bodyTextStyle.copyWith(fontSize: 18 * theme.fontScale),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop('exit');
                  if (theme.isVoiceGuideEnabled) {
                    await _announce("저장하지 않고 종료합니다.");
                  }
                },
                child: Text(
                  '저장 안 함',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.textColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop('save');
                  if (theme.isVoiceGuideEnabled) {
                    await _announce("저장하기를 선택하셨습니다.");
                  }
                },
                child: Text(
                  '저장하기',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (action == 'save') {
      await _saveToPrescriptionBox();
      // 저장 후 화면에 남아있음 (버튼이 자동으로 업데이트됨)
      // 사용자가 다시 "끝내기" 버튼을 누르면 저장된 상태로 바로 홈화면으로 이동
    } else if (action == 'exit') {
      // 저장하지 않고 홈화면으로 이동
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  /// 보관함에 저장 다이얼로그
  Future<void> _showSaveDialog() async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return AlertDialog(
            backgroundColor: theme.backgroundColor,
            title: Text(
              '처방전 저장',
              style: theme.titleStyle.copyWith(fontSize: 24 * theme.fontScale),
            ),
            content: Text(
              '이 처방전을 보관함에 저장하시겠습니까?\n나중에 기록함에서 다시 불러올 수 있습니다.',
              style: theme.bodyTextStyle.copyWith(fontSize: 18 * theme.fontScale),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: Text(
                  '취소',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.textColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('save'),
                child: Text(
                  '저장하기',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (action == 'save') {
      await _saveToPrescriptionBox();
    }
  }

  /// 처방전을 보관함에 저장
  Future<void> _saveToPrescriptionBox() async {
    final theme = context.read<ThemeService>();
    
    try {
      if (theme.isVoiceGuideEnabled) {
        await _announce("보관함에 저장 중입니다.");
      }

      await _prescriptionService.saveTemplate(widget.prescriptionId);

      if (!mounted) return;

      if (theme.isVoiceGuideEnabled) {
        await _announce("보관함에 저장되었습니다.");
      }
      await Vibration.vibrate(duration: 200);

      setState(() {
        _isSaved = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '보관함에 저장되었습니다.',
              style: TextStyle(fontSize: 16 * theme.fontScale),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ [SAVE ERROR] $e");
      if (theme.isVoiceGuideEnabled) {
        await _announce("저장에 실패했습니다.");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '저장에 실패했습니다: ${e.toString()}',
              style: TextStyle(fontSize: 16 * theme.fontScale),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 약 상세 정보 화면으로 이동
  Future<void> _openDrugDetail(dynamic item) async {
    final theme = context.read<ThemeService>();
    
    // 백엔드 응답 구조 확인: selected 객체 안에 있을 수도 있음
    final selected = item['selected'] as Map<String, dynamic>?;
    final itemSeq = selected?['item_seq']?.toString() ?? 
                   item['itemSeq']?.toString() ?? 
                   item['item_seq']?.toString();
    final drugName = selected?['drug_name']?.toString() ?? 
                    item['itemName']?.toString() ?? 
                    item['drug_name']?.toString() ?? 
                    '알약';

    debugPrint('🔍 [약 상세] itemSeq 추출: $itemSeq, drugName: $drugName');
    debugPrint('🔍 [약 상세] item 전체: $item');

    if (itemSeq == null || itemSeq.isEmpty) {
      debugPrint('❌ [약 상세] itemSeq가 없습니다.');
      if (theme.isVoiceGuideEnabled) {
        await _announce("상세 정보를 불러올 수 없습니다.");
      }
      return;
    }

    if (theme.isVoiceGuideEnabled) {
      await _announce("$drugName 상세 정보를 열겠습니다.");
    }
    await Vibration.vibrate(duration: 100);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrugDetailScreen(initialDrugInfo: {'itemSeq': itemSeq}),
      ),
    );
  }

  /// 알약 개수 선택 시트 (약 봉투와 동일한 UI)
  void _showPillCountSheet(String prescriptionId, int defaultCount) {
    if (!mounted) return;

    final maxCount = defaultCount > 0 ? defaultCount : 10; // 최대 10개로 제한
    int currentCount = defaultCount.clamp(1, maxCount);

    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      _announce(
        "알약 촬영 단계로 이동하기 전에, 촬영할 알약 개수를 선택하는 화면입니다. "
        "기본 개수는 ${currentCount}개 입니다.",
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      useSafeArea: true,
      builder: (ctx) {
        return Consumer<ThemeService>(
          builder: (context, theme, child) {
            return Container(
              decoration: BoxDecoration(
                color: theme.backgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: StatefulBuilder(
                builder: (ctx, setModalState) {
                  return Semantics(
                    container: true,
                    label: "알약 개수 선택 화면",
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        Text(
                          "검색할 알약 개수",
                          style: theme.titleStyle.copyWith(
                            fontSize: 24 * theme.fontScale,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "이번에 인식할 알약 사진 개수를 선택해주세요. "
                          "기본값은 처방전에서 인식된 약 개수입니다.",
                          style: theme.subtitleTextStyle.copyWith(
                            fontSize: 16 * theme.fontScale,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Semantics(
                              button: true,
                              label: "알약 개수 줄이기",
                              child: IconButton(
                                onPressed: () {
                                  if (currentCount > 1) {
                                    setModalState(() {
                                      currentCount -= 1;
                                    });
                                  }
                                },
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  size: 30 * theme.fontScale,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              "$currentCount 개",
                              style: theme.titleStyle.copyWith(
                                fontSize: 22 * theme.fontScale,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Semantics(
                              button: true,
                              label: "알약 개수 늘리기",
                              child: IconButton(
                                onPressed: () {
                                  if (currentCount < maxCount) {
                                    setModalState(() {
                                      currentCount += 1;
                                    });
                                  }
                                },
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  size: 30 * theme.fontScale,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                },
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: theme.primaryColor),
                                  foregroundColor: theme.textColor,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: Text(
                                  "취소",
                                  style: theme.buttonTextStyle.copyWith(
                                    fontSize: 18 * theme.fontScale,
                                    color: theme.textColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  _announce(
                                    "총 ${currentCount}개의 알약을 촬영하는 단계로 이동합니다.",
                                  );
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PillCapturePage(
                                        prescriptionId: prescriptionId,
                                        totalCount: currentCount,
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: theme.buttonColor,
                                  foregroundColor: theme.buttonTextColor,
                                ),
                                child: Text(
                                  "알약 촬영 시작",
                                  style: theme.buttonTextStyle.copyWith(
                                    fontSize: 18 * theme.fontScale,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return PopScope(
          canPop: _isSaved,
          onPopInvoked: (didPop) async {
            if (!didPop && !_isSaved) {
              await _showExitDialog();
            }
          },
          child: AccessibleScaffold(
            title: '처방전 분석 결과',
            body: SafeArea(
            child: _loading
                ? LoadingWidget(
                    message: "서버에서 분석 중입니다.\n잠시만 기다려 주세요.",
                  )
                : _error
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 64,
                                color: theme.textColor,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                "결과를 불러오는 데 실패했습니다.",
                                style: theme.titleStyle.copyWith(
                                  fontSize: 24 * theme.fontScale,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              AccessibleButton(
                                label: '다시 시도',
                                icon: Icons.refresh,
                                onPressed: _fetchResult,
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 상단 요약 - 간결하게
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                              decoration: BoxDecoration(
                                color: theme.buttonColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: theme.primaryColor,
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.medication,
                                    color: theme.buttonTextColor,
                                    size: 36,
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      "총 ${_items.length}개의 약이 인식되었습니다",
                                      style: theme.titleStyle.copyWith(
                                        fontSize: 24 * theme.fontScale,
                                        color: theme.buttonTextColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 32),

                            // 약 목록
                            Semantics(
                              header: true,
                              child: Text(
                                "인식된 약 목록",
                                style: theme.titleStyle.copyWith(
                                  fontSize: 24 * theme.fontScale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            if (_items.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: theme.backgroundColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.textColor.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.inbox_outlined,
                                      size: 48,
                                      color: theme.textColor.withOpacity(0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      "결과가 비어 있습니다.",
                                      style: theme.bodyTextStyle.copyWith(
                                        fontSize: 18 * theme.fontScale,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            else
                              ..._items.asMap().entries.map((entry) {
                                final index = entry.key;
                                final item = entry.value as Map? ?? {};

                                // 백엔드 응답 구조 확인: selected 객체 안에 있을 수도 있음
                                final selected = item['selected'] as Map?;
                                final name = selected?['drug_name']?.toString() ?? 
                                            item['itemName']?.toString() ?? 
                                            item['drug_name']?.toString() ?? 
                                            '이름 없음';
                                final onceDose = selected?['onceDose']?.toString() ?? 
                                                item['onceDose']?.toString() ?? '';
                                final dayDose = selected?['dayDose']?.toString() ?? 
                                               item['dayDose']?.toString() ?? '';
                                final totalDose = selected?['totalDose']?.toString() ?? 
                                                 item['totalDose']?.toString() ?? '';
                                final itemSeq = selected?['item_seq']?.toString() ?? 
                                               item['itemSeq']?.toString() ?? 
                                               item['item_seq']?.toString();

                                String doseText = '';
                                if (onceDose.isNotEmpty ||
                                    dayDose.isNotEmpty ||
                                    totalDose.isNotEmpty) {
                                  doseText = "1회 $onceDose / 1일 $dayDose / 총 $totalDose일";
                                }

                                // 해당 약의 복약 안내 찾기
                                String? pillGuide;
                                if (_sequenceText.isNotEmpty && index < _sequenceText.length) {
                                  pillGuide = _sequenceText[index];
                                }

                                final hasDetail = itemSeq != null && itemSeq.isNotEmpty;
                                return Semantics(
                                  button: hasDetail,
                                  label: "${index + 1}번째 약: $name${doseText.isNotEmpty ? ', $doseText' : ''}${pillGuide != null ? '. $pillGuide' : ''}${hasDetail ? '. 탭하면 상세 정보를 확인할 수 있습니다.' : '. 상세 정보가 제공되지 않습니다.'}",
                                  child: Container(
                                    margin: EdgeInsets.only(bottom: index < _items.length - 1 ? 16 : 0),
                                    decoration: BoxDecoration(
                                      color: theme.buttonColor,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: theme.primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: itemSeq != null && itemSeq.isNotEmpty
                                            ? () => _openDrugDetail(item)
                                            : null,
                                        borderRadius: BorderRadius.circular(16),
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  // 번호 표시
                                                  Container(
                                                    width: 48,
                                                    height: 48,
                                                    decoration: BoxDecoration(
                                                      color: theme.primaryColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '${index + 1}',
                                                        style: theme.buttonTextStyle.copyWith(
                                                          fontSize: 22 * theme.fontScale,
                                                          fontWeight: FontWeight.bold,
                                                          color: theme.buttonTextColor,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  // 약 이름
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      style: theme.titleStyle.copyWith(
                                                        fontSize: 22 * theme.fontScale,
                                                        color: theme.buttonTextColor,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  // 상세 정보 아이콘 또는 정보 없음 표시
                                                  if (itemSeq != null && itemSeq.isNotEmpty)
                                                    Icon(
                                                      Icons.arrow_forward_ios,
                                                      color: theme.buttonTextColor,
                                                      size: 20,
                                                    )
                                                  else
                                                    Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.info_outline,
                                                          color: theme.buttonTextColor.withOpacity(0.6),
                                                          size: 18,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '상세정보 없음',
                                                          style: theme.bodyTextStyle.copyWith(
                                                            fontSize: 12 * theme.fontScale,
                                                            color: theme.buttonTextColor.withOpacity(0.6),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                              // 복약 안내
                                              if (pillGuide != null) ...[
                                                const SizedBox(height: 12),
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: theme.backgroundColor,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Icon(
                                                        Icons.info_outline,
                                                        size: 18,
                                                        color: theme.primaryColor,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          pillGuide,
                                                          style: theme.bodyTextStyle.copyWith(
                                                            fontSize: 16 * theme.fontScale,
                                                          ),
                                                          maxLines: 3,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              // 투약량 정보
                                              if (doseText.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.medication_liquid,
                                                      size: 16,
                                                      color: theme.buttonTextColor.withOpacity(0.7),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        doseText,
                                                        style: theme.bodyTextStyle.copyWith(
                                                          fontSize: 16 * theme.fontScale,
                                                          color: theme.buttonTextColor.withOpacity(0.8),
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),

                            const SizedBox(height: 32),

                            // 알약 촬영하기 버튼 (알약 촬영이 완료되지 않은 경우만 표시)
                            if (!widget.pillsCaptured) ...[
                              AccessibleButton(
                                label: '알약 촬영하기',
                                icon: Icons.camera_alt,
                                hint: '인식된 약들을 촬영하여 확인합니다',
                                onPressed: () => _showPillCountSheet(widget.prescriptionId, widget.totalCount),
                                height: 56,
                              ),
                              const SizedBox(height: 12),
                            ],

                            // 보관함에 저장 버튼 (저장되지 않은 경우만)
                            if (!_isSaved)
                              AccessibleButton(
                                label: '보관함에 저장',
                                icon: Icons.save,
                                hint: '처방전 분석 결과를 보관함에 저장합니다',
                                onPressed: () => _showSaveDialog(),
                                height: 56,
                                backgroundColor: theme.buttonColor.withOpacity(0.8),
                              ),

                            if (!_isSaved) const SizedBox(height: 12),

                            // 끝내기 버튼
                            AccessibleButton(
                              label: _isSaved ? '끝내기' : '저장하지 않고 끝내기',
                              icon: _isSaved ? Icons.check_circle : Icons.exit_to_app,
                              hint: _isSaved 
                                  ? '처방전이 저장되었습니다. 화면을 종료합니다.'
                                  : '화면을 종료합니다. 저장 여부를 선택할 수 있습니다.',
                              onPressed: _showExitDialog,
                            ),

                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
            ),
          ),
        );
      },
    );
  }
}
