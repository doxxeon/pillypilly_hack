import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../../services/theme_service.dart';
import '../../services/prescription_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import '../../widgets/loading_widget.dart';
import '../upload_page_screens/pill_capture.dart';
import '../details/drug_detail.dart';

class KeepingScreen extends StatefulWidget {
  const KeepingScreen({Key? key}) : super(key: key);

  @override
  State<KeepingScreen> createState() => _KeepingScreenState();
}

class _KeepingScreenState extends State<KeepingScreen> {
  final PrescriptionService _prescriptionService = PrescriptionService();
  final FlutterTts _tts = FlutterTts();
  
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _announce(String text) async {
    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
    }
  }

  /// 날짜 문자열을 연월일 형식으로 변환 (예: 2025-11-17T21:57:26 → 2025년 11월 17일)
  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    
    try {
      // ISO 8601 형식 파싱 시도 (2025-11-17T21:57:26)
      DateTime? date;
      if (dateString.contains('T')) {
        // T 이전 부분만 추출 (2025-11-17)
        final datePart = dateString.split('T')[0];
        final parts = datePart.split('-');
        if (parts.length == 3) {
          final year = int.tryParse(parts[0]);
          final month = int.tryParse(parts[1]);
          final day = int.tryParse(parts[2]);
          if (year != null && month != null && day != null) {
            date = DateTime(year, month, day);
          }
        }
      } else {
        // 다른 형식도 시도
        date = DateTime.tryParse(dateString);
      }
      
      if (date != null) {
        return '${date.year}년 ${date.month}월 ${date.day}일';
      }
    } catch (e) {
      debugPrint('날짜 파싱 오류: $e');
    }
    
    // 파싱 실패 시 원본 반환 (또는 빈 문자열)
    return dateString;
  }

  /// ⑤ 기록함에서 처방전 불러오기 → /prescriptions/templates
  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final templates = await _prescriptionService.getTemplates();
      setState(() {
        _templates = templates;
        _isLoading = false;
      });
      
      if (templates.isEmpty) {
        await _announce("저장된 처방전이 없습니다.");
      } else {
        await _announce("총 ${templates.length}개의 저장된 처방전이 있습니다. 각 처방전을 탭하면 알약 촬영을 시작할 수 있습니다.");
        await Vibration.vibrate(duration: 200);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "처방전 목록을 불러오는 중 오류가 발생했습니다: ${e.toString()}";
        _isLoading = false;
      });
      await _announce("처방전 목록을 불러오는 중 오류가 발생했습니다.");
    }
  }

  /// ⑥ 새로운 세션 생성 → /prescriptions/{template_id}/start-session
  Future<void> _selectTemplate(Map<String, dynamic> template) async {
    final templateId = template['id']?.toString() ?? template['template_id']?.toString();
    if (templateId == null) {
      await _announce("처방전 정보가 올바르지 않습니다.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _announce("처방전을 불러오는 중입니다.");
      final sessionResult = await _prescriptionService.startSession(templateId);
      
      // 디버깅: 응답 구조 확인
      debugPrint('🔍 [보관함] 세션 생성 응답: $sessionResult');
      
      // 여러 가능한 필드명 시도 (API 응답에 따라 'new prescription_idd' 또는 'new_prescription_id' 등)
      final prescriptionId = sessionResult['new prescription_idd']?.toString() ??
                             sessionResult['new_prescription_idd']?.toString() ??
                             sessionResult['new prescription_id']?.toString() ??
                             sessionResult['new_prescription_id']?.toString() ??
                             sessionResult['prescription_id']?.toString() ?? 
                             sessionResult['prescriptionId']?.toString() ??
                             sessionResult['id']?.toString() ??
                             (sessionResult['data'] is Map ? sessionResult['data']['prescription_id']?.toString() : null);
      
      final drugCount = sessionResult['drug_count'] ?? 
                       sessionResult['drugCount'] ??
                       sessionResult['expected_count'] ??
                       sessionResult['expectedCount'] ??
                       sessionResult['total_count'] ??
                       sessionResult['totalCount'] ??
                       template['drug_count'] ?? 
                       template['total_count'] ??
                       1;
      
      // 약 목록 추출
      final drugList = sessionResult['drug_list'] ?? 
                      sessionResult['drugList'] ??
                      sessionResult['drugs'] ??
                      <dynamic>[];
      
      debugPrint('🔍 [보관함] 추출된 prescriptionId: $prescriptionId');
      debugPrint('🔍 [보관함] 추출된 drugCount: $drugCount');
      debugPrint('🔍 [보관함] 추출된 drugList: $drugList');
      
      if (prescriptionId == null || prescriptionId.isEmpty) {
        debugPrint('❌ [보관함] prescription_id를 찾을 수 없습니다. 응답: $sessionResult');
        throw Exception('세션 생성 실패: prescription_id가 없습니다. 응답: ${sessionResult.toString()}');
      }

      setState(() {
        _isLoading = false;
      });

      await _announce("처방전이 불러와졌습니다. 약 목록을 확인할 수 있습니다.");
      
      if (mounted) {
        // 약 목록 화면으로 이동
        _showDrugList(
          prescriptionId: prescriptionId,
          drugList: drugList is List ? drugList : [],
          drugCount: drugCount is int ? drugCount : int.tryParse(drugCount.toString()) ?? 1,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = "세션 생성 중 오류가 발생했습니다: ${e.toString()}";
        _isLoading = false;
      });
      await _announce("세션 생성 중 오류가 발생했습니다.");
    }
  }

  /// 알약 개수 선택 시트 (처방전 업로드와 동일한 UI)
  void _showPillCountSheet(String prescriptionId, int defaultCount, int maxCount) {
    if (!mounted) return;

    int currentCount = defaultCount.clamp(1, maxCount > 0 ? maxCount : defaultCount);

    _announce(
      "알약 촬영 단계로 이동하기 전에, 촬영할 알약 개수를 선택하는 화면입니다. "
      "기본 개수는 ${currentCount}개 입니다.",
    );

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
                                  final max = maxCount > 0 ? maxCount : defaultCount;
                                  if (currentCount < max) {
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
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: Text(
                                  "취소",
                                  style: theme.buttonTextStyle.copyWith(
                                    fontSize: 18 * theme.fontScale,
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

  /// 약 목록을 보여주는 화면
  void _showDrugList({
    required String prescriptionId,
    required List<dynamic> drugList,
    required int drugCount,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // 헤더
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.primaryColor.withOpacity(0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          label: "처방전 약 목록. 총 ${drugList.length}개의 약이 있습니다.",
                          child: Text(
                            "처방전 약 목록",
                            style: theme.titleStyle.copyWith(
                              fontSize: 24 * theme.fontScale,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        tooltip: "닫기",
                      ),
                    ],
                  ),
                ),
                // 약 목록
                Expanded(
                  child: drugList.isEmpty
                      ? Center(
                          child: Semantics(
                            label: "약 목록이 비어 있습니다",
                            child: Text(
                              "약 목록이 비어 있습니다",
                              style: theme.bodyTextStyle.copyWith(
                                fontSize: 18 * theme.fontScale,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: drugList.length,
                          itemBuilder: (context, index) {
                            final drug = drugList[index] as Map<String, dynamic>? ?? {};
                            final itemName = drug['itemName']?.toString() ?? 
                                           drug['drug_name']?.toString() ?? 
                                           '이름 없음';
                            final itemSeq = drug['itemSeq']?.toString() ?? 
                                          drug['item_seq']?.toString();

                            return Semantics(
                              button: itemSeq != null && itemSeq.isNotEmpty,
                              label: "${index + 1}번 약: $itemName${itemSeq != null && itemSeq.isNotEmpty ? '. 탭하면 상세 정보를 확인할 수 있습니다.' : ''}",
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                color: theme.backgroundColor.withOpacity(0.1),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: itemSeq != null && itemSeq.isNotEmpty
                                        ? () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => DrugDetailScreen(
                                                  initialDrugInfo: {'itemSeq': itemSeq},
                                                ),
                                              ),
                                            );
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(12),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      leading: Container(
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
                                              fontSize: 20 * theme.fontScale,
                                              fontWeight: FontWeight.bold,
                                              color: theme.buttonTextColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        itemName,
                                        style: theme.bodyTextStyle.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20 * theme.fontScale,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: itemSeq != null && itemSeq.isNotEmpty
                                          ? Icon(
                                              Icons.arrow_forward_ios,
                                              color: theme.primaryColor,
                                              size: 20,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // 하단 버튼
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.primaryColor.withOpacity(0.2)),
                    ),
                  ),
                  child: Column(
                    children: [
                      AccessibleButton(
                        label: "알약 촬영하기",
                        icon: Icons.camera_alt,
                        hint: "인식된 약들을 촬영하여 확인합니다",
                        onPressed: () {
                          Navigator.pop(context);
                          _showPillCountSheet(prescriptionId, drugCount, drugList.length);
                        },
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: theme.primaryColor),
                        ),
                        child: Text(
                          "닫기",
                          style: theme.buttonTextStyle.copyWith(
                            fontSize: 18 * theme.fontScale,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '보관함',
          body: _isLoading
              ? const LoadingWidget(message: "처방전 목록을 불러오는 중...")
              : _errorMessage != null
                  ? CustomErrorWidget(
                      message: _errorMessage!,
                      onRetry: _loadTemplates,
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '저장된 처방전',
                                style: theme.titleStyle.copyWith(
                                  fontSize: 24 * theme.fontScale,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.refresh, color: theme.primaryColor),
                                onPressed: _loadTemplates,
                                tooltip: '새로고침',
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _templates.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.folder_open,
                                        size: 64,
                                        color: theme.textColor.withOpacity(0.3),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        '저장된 처방전이 없습니다',
                                        style: theme.bodyTextStyle.copyWith(
                                          fontSize: 18 * theme.fontScale,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: _templates.length,
                                  itemBuilder: (context, index) {
                                    final template = _templates[index];
                                    final name = template['name']?.toString() ?? 
                                                 template['prescription_name']?.toString() ?? 
                                                 '처방전 ${index + 1}';
                                    final dateString = template['created_at']?.toString() ?? 
                                                       template['date']?.toString() ?? '';
                                    final formattedDate = _formatDate(dateString);
                                    final drugCount = template['drug_count']?.toString() ?? '';

                                    return Semantics(
                                      button: true,
                                      label: "${index + 1}번째 처방전: $name. ${formattedDate.isNotEmpty ? '저장일: $formattedDate. ' : ''}${drugCount.isNotEmpty ? '약 $drugCount개. ' : ''}탭하면 알약 촬영을 시작합니다.",
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 16),
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
                                            onTap: () {
                                              Vibration.vibrate(duration: 100);
                                              _selectTemplate(template);
                                            },
                                            borderRadius: BorderRadius.circular(16),
                                            child: Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Row(
                                                children: [
                                                  // 아이콘
                                                  Container(
                                                    width: 56,
                                                    height: 56,
                                                    decoration: BoxDecoration(
                                                      color: theme.primaryColor,
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Icon(
                                                      Icons.description,
                                                      color: theme.buttonTextColor,
                                                      size: 32,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  // 정보
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          name,
                                                          style: theme.titleStyle.copyWith(
                                                            fontSize: 20 * theme.fontScale,
                                                            color: theme.buttonTextColor,
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        const SizedBox(height: 8),
                                                        if (formattedDate.isNotEmpty) ...[
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Icons.calendar_today,
                                                                size: 16,
                                                                color: theme.buttonTextColor.withOpacity(0.7),
                                                              ),
                                                              const SizedBox(width: 6),
                                                              Text(
                                                                formattedDate,
                                                                style: theme.bodyTextStyle.copyWith(
                                                                  fontSize: 16 * theme.fontScale,
                                                                  color: theme.buttonTextColor.withOpacity(0.8),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          if (drugCount.isNotEmpty) const SizedBox(height: 4),
                                                        ],
                                                        if (drugCount.isNotEmpty)
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Icons.medication,
                                                                size: 16,
                                                                color: theme.buttonTextColor.withOpacity(0.7),
                                                              ),
                                                              const SizedBox(width: 6),
                                                              Text(
                                                                '약 $drugCount개',
                                                                style: theme.bodyTextStyle.copyWith(
                                                                  fontSize: 16 * theme.fontScale,
                                                                  color: theme.buttonTextColor.withOpacity(0.8),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  // 화살표
                                                  Icon(
                                                    Icons.arrow_forward_ios,
                                                    color: theme.buttonTextColor,
                                                    size: 20,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}