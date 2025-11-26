import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:pillypilly_h/screens/search_screens/search_screen.dart';
import 'package:pillypilly_h/screens/upload_page_screens/upload_page_screen.dart';
import 'package:pillypilly_h/screens/box_screens/box_screen.dart';
import 'package:pillypilly_h/screens/keeping_screens/keeping_screen.dart';
import 'package:pillypilly_h/screens/setting_screens/settings_screen.dart';

import 'package:pillypilly_h/services/theme_service.dart';
import 'package:pillypilly_h/widgets/accessible_scaffold.dart';
import 'package:pillypilly_h/services/tts_service.dart' as tts_opt;

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // 쨍한 오렌지
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kOrangePressed = Color(0xFFE66E00);
  static const Color kShadow = Colors.black12;

  final List<_Feature> features = [
    _Feature('의약품 검색하기', Icons.search, (ctx) => SearchScreen()),
    _Feature('처방전 약봉투 분석', Icons.upload_file, (ctx) => UploadPageScreen()),
    _Feature('약 상자 인식', Icons.qr_code_scanner, (ctx) => BoxScreen()),
    _Feature('처방전 약봉투 보관함', Icons.folder, (ctx) => KeepingScreen()),
    _Feature('설정', Icons.settings, (ctx) => const SettingsScreen()),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _speak(context, '메인 화면입니다. 원하는 기능을 선택하세요.');
    });
  }

  Future<void> _speak(BuildContext ctx, String text) async {
    try {
      await tts_opt.TTSService().speak(text);
    } catch (_) {}
  }

  Future<void> _onTapFeature(BuildContext context, _Feature feature) async {
    HapticFeedback.lightImpact();
    await _speak(context, '${feature.title} 화면으로 이동합니다.');
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: feature.routeBuilder));
  }

  // 버튼 위젯 리스트 생성 (중복 방지)
  List<Widget> _buildButtons() {
    return List.generate(features.length, (index) {
      final feature = features[index];
      return _OrangeTallButton(
        title: feature.title,
        icon: feature.icon,
        onTap: () => _onTapFeature(context, feature),
        onLongPress: () => _speak(context, feature.title),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: 'Pillypilly',
          body: LayoutBuilder(
            builder: (context, constraints) {
              // 콘텐츠의 대략적 총 높이 계산 (버튼 높이 추정 + 간격 + 패딩)
              const double itemHeight = 88; // _OrangeTallButton의 패딩/폰트 기준 추정
              const double spacing = 16;
              const double verticalPadding = 20 * 2;

              final double estimated =
                  features.length * itemHeight +
                  (features.length - 1) * spacing +
                  verticalPadding;

              final bool canCenter = estimated <= constraints.maxHeight;

              if (canCenter) {
                // 화면에 여유가 있으면 "가운데 정렬" (폰마다 자동 중앙 배치)
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < features.length; i++) ...[
                            _buildButtons()[i],
                            if (i != features.length - 1)
                              const SizedBox(height: spacing),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              } else {
                // 공간이 부족하면 "스크롤 리스트"
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: ListView.separated(
                    itemCount: features.length,
                    separatorBuilder: (_, __) => const SizedBox(height: spacing),
                    itemBuilder: (context, index) =>
                        _buildButtons()[index],
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}

class _OrangeTallButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _OrangeTallButton({
    Key? key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  State<_OrangeTallButton> createState() => _OrangeTallButtonState();
}

class _OrangeTallButtonState extends State<_OrangeTallButton> {
  bool _pressed = false;

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kOrangePressed = Color(0xFFE66E00);
  static const Color kShadow = Colors.black26;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.title,
      hint: '두 번 탭하면 열립니다. 길게 누르면 음성 안내가 재생됩니다.',
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
          decoration: BoxDecoration(
            color: _pressed ? kOrangePressed : kOrange,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: kShadow,
                blurRadius: _pressed ? 2 : 8,
                offset: Offset(0, _pressed ? 1 : 4),
              ),
            ],
          ),
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: () {
              HapticFeedback.selectionClick();
              widget.onLongPress?.call();
            },
            borderRadius: BorderRadius.circular(18),
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 36, color: Colors.white),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20 * context.watch<ThemeService>().fontScale,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature {
  final String title;
  final IconData icon;
  final Widget Function(BuildContext) routeBuilder;

  _Feature(this.title, this.icon, this.routeBuilder);
}