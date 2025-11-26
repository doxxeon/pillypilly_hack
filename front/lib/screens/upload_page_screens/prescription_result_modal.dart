// lib/screens/upload_page_screens/prescription_result_modal.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../services/prescription_service.dart';
import '../../widgets/accessible_button.dart';
import '../details/drug_detail.dart';
import 'pill_capture.dart';

/// 처방전 결과 모달 (약 봉투 결과와 동일한 UI)
class PrescriptionResultModal extends StatefulWidget {
  final String prescriptionId;
  final int totalItems;
  final List<dynamic> initialResults;
  final ThemeService theme;
  final bool pillsCaptured; // 알약 촬영 완료 여부

  const PrescriptionResultModal({
    Key? key,
    required this.prescriptionId,
    required this.totalItems,
    required this.initialResults,
    required this.theme,
    this.pillsCaptured = false, // 기본값은 false
  }) : super(key: key);

  @override
  State<PrescriptionResultModal> createState() => _PrescriptionResultModalState();
}

class _PrescriptionResultModalState extends State<PrescriptionResultModal> {
  bool _isSaved = false;
  final PrescriptionService _prescriptionService = PrescriptionService();

  void _showPillCountSheet(String prescriptionId, int defaultCount) {
    if (!mounted) return;

    final maxCount = defaultCount > 0 ? defaultCount : 10;
    int currentCount = defaultCount.clamp(1, maxCount);

    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      // TTS는 여기서 처리하지 않고, PillCapturePage에서 처리
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
                                  Navigator.of(ctx).pop(); // 개수 선택 시트 닫기
                                  Navigator.of(context).pop(); // 결과 모달 닫기
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
      try {
        await _prescriptionService.saveTemplate(widget.prescriptionId);
        if (mounted) {
          setState(() {
            _isSaved = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '보관함에 저장되었습니다.',
                style: TextStyle(fontSize: 16 * widget.theme.fontScale),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '저장에 실패했습니다: ${e.toString()}',
                style: TextStyle(fontSize: 16 * widget.theme.fontScale),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleClose() async {
    if (_isSaved) {
      Navigator.pop(context);
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
      try {
        await _prescriptionService.saveTemplate(widget.prescriptionId);
        if (mounted) {
          setState(() {
            _isSaved = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '보관함에 저장되었습니다.',
                style: TextStyle(fontSize: 16 * widget.theme.fontScale),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '저장에 실패했습니다: ${e.toString()}',
                style: TextStyle(fontSize: 16 * widget.theme.fontScale),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (action == 'exit') {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
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
                        label: "처방전 분석 결과. 총 ${widget.totalItems}개의 약이 인식되었습니다.",
                        child: Text(
                          "처방전 분석 결과",
                          style: theme.titleStyle.copyWith(
                            fontSize: 26 * theme.fontScale,
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
              // 결과 리스트
              Expanded(
                child: widget.initialResults.isEmpty
                    ? Center(
                        child: Semantics(
                          label: "인식된 약이 없습니다",
                          child: Text(
                            "인식된 약이 없습니다",
                            style: theme.bodyTextStyle.copyWith(
                              fontSize: 20 * theme.fontScale,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: widget.initialResults.length,
                        itemBuilder: (context, index) {
                          final item = widget.initialResults[index] as Map<String, dynamic>;
                          // 백엔드 응답 구조 확인: selected 객체 안에 있을 수도 있음
                          final selected = item['selected'] as Map<String, dynamic>?;
                          final itemName = selected?['drug_name']?.toString() ?? 
                                          item['itemName']?.toString() ?? 
                                          item['drug_name']?.toString() ?? 
                                          '이름 없음';
                          final itemSeq = selected?['item_seq']?.toString() ?? 
                                         item['itemSeq']?.toString() ?? 
                                         item['item_seq']?.toString();
                          
                          debugPrint('🔍 [처방전 모달] ${index + 1}번 약: itemName=$itemName, itemSeq=$itemSeq');
                          debugPrint('🔍 [처방전 모달] item 전체: $item');
                          if (selected != null) {
                            debugPrint('🔍 [처방전 모달] selected: $selected');
                          }
                          final onceDose = selected?['onceDose']?.toString() ?? 
                                          item['onceDose']?.toString() ?? '';
                          final dayDose = selected?['dayDose']?.toString() ?? 
                                         item['dayDose']?.toString() ?? '';
                          final totalDose = selected?['totalDose']?.toString() ?? 
                                           item['totalDose']?.toString() ?? '';

                          return Semantics(
                            button: itemSeq != null && itemSeq.isNotEmpty,
                            label: "${index + 1}번 약: $itemName. "
                                "${onceDose.isNotEmpty ? '1회 $onceDose. ' : ''}"
                                "${dayDose.isNotEmpty ? '1일 $dayDose회. ' : ''}"
                                "${totalDose.isNotEmpty ? '총 $totalDose일. ' : ''}"
                                "${itemSeq != null && itemSeq.isNotEmpty ? '탭하면 상세 정보를 확인할 수 있습니다.' : ''}",
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: theme.backgroundColor.withOpacity(0.1),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: (itemSeq != null && itemSeq.isNotEmpty)
                                      ? () {
                                          debugPrint('🔍 [처방전 모달] 약 상세 정보 진입: itemSeq=$itemSeq, itemName=$itemName');
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => DrugDetailScreen(
                                                initialDrugInfo: {'itemSeq': itemSeq},
                                              ),
                                            ),
                                          );
                                        }
                                      : () {
                                          debugPrint('❌ [처방전 모달] 약 상세 정보 진입 불가: itemSeq가 없음 (itemName=$itemName)');
                                        },
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: Icon(
                                      Icons.medication,
                                      color: theme.primaryColor,
                                      size: 32,
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
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (onceDose.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              "1회 투약량: $onceDose",
                                              style: theme.subtitleTextStyle.copyWith(
                                                fontSize: 18 * theme.fontScale,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        if (dayDose.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              "1일 투여 횟수: $dayDose",
                                              style: theme.subtitleTextStyle.copyWith(
                                                fontSize: 18 * theme.fontScale,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        if (totalDose.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              "총 투약 일수: $totalDose",
                                              style: theme.subtitleTextStyle.copyWith(
                                                fontSize: 18 * theme.fontScale,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: (itemSeq != null && itemSeq.isNotEmpty)
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
                child: StatefulBuilder(
                  builder: (context, setModalState) {
                    return Column(
                      children: [
                        // 알약 촬영하기 버튼 (알약 촬영이 완료되지 않은 경우만 표시)
                        if (!widget.pillsCaptured) ...[
                          AccessibleButton(
                            label: "알약 촬영하기",
                            icon: Icons.camera_alt,
                            hint: "인식된 약들을 촬영하여 확인합니다",
                            onPressed: () {
                              _showPillCountSheet(widget.prescriptionId, widget.totalItems);
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (!_isSaved)
                          AccessibleButton(
                            label: "보관함에 저장",
                            icon: Icons.save,
                            hint: "처방전 분석 결과를 보관함에 저장합니다",
                            onPressed: () async {
                              await _showSaveDialog();
                              setModalState(() {});
                            },
                            height: 50,
                            backgroundColor: theme.buttonColor.withOpacity(0.8),
                          ),
                        if (!_isSaved) const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _handleClose(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: BorderSide(color: theme.primaryColor),
                          ),
                          child: Text(
                            _isSaved ? "닫기" : "저장하지 않고 닫기",
                            style: theme.bodyTextStyle.copyWith(color: theme.primaryColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

