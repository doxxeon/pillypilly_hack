// front/lib/screens/upload_page_screens/upload_page_screen.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import 'drugbag_ocr_screen.dart';  // 약봉투 OCR 페이지
import 'prescription_ocr_screen.dart';  // 처방전 OCR 페이지

class UploadPageScreen extends StatefulWidget {
  const UploadPageScreen({Key? key}) : super(key: key);

  @override
  State<UploadPageScreen> createState() => _UploadPageScreenState();
}

class _UploadPageScreenState extends State<UploadPageScreen> {


  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        final cs = Theme.of(context).colorScheme;
        return AccessibleScaffold(
          title: '처방전/약봉투 업로드',
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 한 줄 설명
                Semantics(
                  label: "처방전이나 약봉투를 업로드해 복용약을 인식합니다",
                  child: Text(
                    '처방전이나 약봉투를 업로드해 복용약을 인식합니다.',
                    style: theme.bodyTextStyle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 24),

                // 타입 선택 섹션
                Semantics(
                  header: true,
                  label: "업로드할 종류를 선택하세요",
                  child: Text(
                    '업로드할 종류를 선택하세요',
                    style: theme.titleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 16),

                // 처방전 버튼
                AccessibleButton(
                  label: '처방전 업로드',
                  icon: Icons.description,
                  hint: '처방전 이미지를 업로드하여 약 정보를 인식합니다',
                  onPressed: () => _showPrescriptionOptions(),
                  height: 64,
                ),
                const SizedBox(height: 12),

                // 약봉투 버튼
                AccessibleButton(
                  label: '약봉투 업로드',
                  icon: Icons.medication,
                  hint: '약봉투 이미지를 업로드하여 약 정보를 인식합니다',
                  onPressed: () => _showDrugbagOptions(),
                  height: 64,
                  backgroundColor: theme.buttonColor.withOpacity(0.8),
                ),

                const SizedBox(height: 24),

                // 가이드 카드
                _GuideCard(
                  items: const [
                    _GuideItem(
                      icon: Icons.stay_current_portrait,
                      text: '세로 방향으로 꽉 차게 촬영',
                    ),
                    _GuideItem(
                      icon: Icons.wb_sunny_outlined,
                      text: '반사/그림자 최소화, 또렷하게',
                    ),
                    _GuideItem(
                      icon: Icons.shield_outlined,
                      text: '개인정보 영역은 자동 마스킹 처리',
                    ),
                  ],
                ),
                const Spacer(),

                // 작은 프라이버시 문구
                Semantics(
                  label: "업로드된 이미지는 약 인식 목적에만 사용되며 안전하게 처리됩니다",
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '업로드된 이미지는 약 인식 목적에만 사용되며 안전하게 처리됩니다.',
                          style: theme.subtitleTextStyle.copyWith(fontSize: 12),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPrescriptionOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return Container(
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  label: "처방전 업로드 방법 선택",
                  child: Text(
                    '처방전 업로드 방법 선택',
                    style: theme.titleStyle,
                  ),
                ),
                const SizedBox(height: 24),
                AccessibleButton(
                  label: '카메라로 촬영하기',
                  icon: Icons.photo_camera,
                  hint: '카메라로 처방전을 촬영합니다',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrescriptionOcrScreen(
                          initialSource: ImageSource.camera,
                        ),
                      ),
                    );
                  },
                  height: 64,
                ),
                const SizedBox(height: 12),
                AccessibleButton(
                  label: '갤러리에서 선택하기',
                  icon: Icons.photo_library,
                  hint: '갤러리에서 처방전 이미지를 선택합니다',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrescriptionOcrScreen(
                          initialSource: ImageSource.gallery,
                        ),
                      ),
                    );
                  },
                  height: 64,
                  backgroundColor: theme.buttonColor.withOpacity(0.8),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: theme.primaryColor),
                  ),
                  child: Text(
                    '취소',
                    style: theme.bodyTextStyle.copyWith(color: theme.primaryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDrugbagOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return Container(
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  label: "약봉투 업로드 방법 선택",
                  child: Text(
                    '약봉투 업로드 방법 선택',
                    style: theme.titleStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 24),
                AccessibleButton(
                  label: '카메라로 촬영하기',
                  icon: Icons.photo_camera,
                  hint: '카메라로 약봉투를 촬영합니다',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DrugbagOcrScreen(
                          initialSource: ImageSource.camera,
                        ),
                      ),
                    );
                  },
                  height: 64,
                ),
                const SizedBox(height: 12),
                AccessibleButton(
                  label: '갤러리에서 선택하기',
                  icon: Icons.photo_library,
                  hint: '갤러리에서 약봉투 이미지를 선택합니다',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DrugbagOcrScreen(
                          initialSource: ImageSource.gallery,
                        ),
                      ),
                    );
                  },
                  height: 64,
                  backgroundColor: theme.buttonColor.withOpacity(0.8),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: theme.primaryColor),
                  ),
                  child: Text(
                    '취소',
                    style: theme.bodyTextStyle.copyWith(color: theme.primaryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────
// Guide 카드(텍스트만 깔끔히 노출; UI에서 벗어나지 않는 미시 카피 강화)
// ───────────────────────────────────────────────────────────

class _GuideCard extends StatelessWidget {
  final List<_GuideItem> items;
  const _GuideCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final border = BorderSide(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
      width: 1,
    );
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.fromBorderSide(border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map(
              (it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(it.icon, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          it.text,
                          style: TextStyle(
                            fontSize: 14 * context.watch<ThemeService>().fontScale,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _GuideItem {
  final IconData icon;
  final String text;
  const _GuideItem({required this.icon, required this.text});
}