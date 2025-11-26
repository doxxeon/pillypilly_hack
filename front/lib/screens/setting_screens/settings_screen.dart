import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pillypilly_h/services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();

    return AccessibleScaffold(
      title: '설정',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== 음성 안내 토글 =====
          Card(
            color: theme.isHighContrastEnabled ? Colors.black : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              value: theme.isVoiceGuideEnabled,
              onChanged: (v) async {
                await context.read<ThemeService>().toggleVoiceGuide(v);
              },
              activeColor: theme.primaryColor,
              title: Text('음성 안내', style: theme.titleStyle),
              subtitle: Text(
                '시각장애인을 위한 음성 안내를 켜거나 끕니다.',
                style: theme.subtitleTextStyle,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== (옵션) 글자 크기 =====
          Card(
            color: theme.isHighContrastEnabled ? Colors.black : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text('글자 크기', style: theme.titleStyle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Slider(
                    value: theme.fontScale,
                    onChanged: (v) => context.read<ThemeService>().updateFontScale(v),
                    min: 0.8,
                    max: 2.0,
                    divisions: 12,
                    label: '${(theme.fontScale * 100).round()}%',
                    activeColor: theme.primaryColor,
                  ),
                  Text('현재: ${(theme.fontScale * 100).round()}%', style: theme.subtitleTextStyle),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ===== (옵션) 고대비 모드 =====
          Card(
            color: theme.isHighContrastEnabled ? Colors.black : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              value: theme.isHighContrastEnabled,
              onChanged: (v) => context.read<ThemeService>().updateHighContrast(v),
              activeColor: theme.primaryColor,
              title: Text('고대비 모드', style: theme.titleStyle),
              subtitle: Text(
                '저시력 사용자를 위한 대비 강화 모드입니다.',
                style: theme.subtitleTextStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}