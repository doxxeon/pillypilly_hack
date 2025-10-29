import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../services/theme_service.dart';
import '../../services/settings_service.dart';
import '../../services/tts_profiles.dart';
import '../../widgets/accessible_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final FlutterTts _flutterTts;
  late final TTSProfiles _ttsProfiles;
  String _selectedTtsProfile = 'softFemale';

  @override
  void initState() {
    super.initState();

    // ✅ TTS 객체 초기화
    _flutterTts = FlutterTts();
    _ttsProfiles = TTSProfiles(_flutterTts);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<ThemeService>().refreshSettings();
      _selectedTtsProfile = await SettingsService.getTtsProfile();
      setState(() {});
    });
  }

  /// 🔊 음성 프로필 변경 처리
  Future<void> _onTtsProfileChanged(String? value) async {
    if (value == null) return;
    await SettingsService.setTtsProfile(value);
    setState(() => _selectedTtsProfile = value);

    // ✅ 프로필 적용
    switch (value) {
      case 'deepMale':
        await _ttsProfiles.deepMale();
        break;
      case 'assistantTone':
        await _ttsProfiles.assistantTone();
        break;
      case 'robotic':
        await _ttsProfiles.robotic();
        break;
      default:
        await _ttsProfiles.softFemale();
    }

    await _ttsProfiles.speak("안녕하세요, 필리필리입니다. 선택한 음성 프로필이 적용되었습니다.");
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: "설정",
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 🎙 음성 안내
              SwitchListTile(
                title: Text(
                  "음성 안내",
                  style: theme.buttonTextStyle.copyWith(fontSize: 18 * theme.fontScale),
                ),
                subtitle: Text(
                  "시각장애인을 위한 음성 안내를 켜거나 끕니다.",
                  style: theme.subtitleTextStyle,
                ),
                value: theme.isVoiceGuideEnabled,
                onChanged: (v) => theme.updateVoiceGuide(v),
                activeColor: Colors.tealAccent,
              ),
              const Divider(),

              // 🗣️ 음성 스타일 선택
              ListTile(
                title: Text(
                  "음성 스타일 선택",
                  style: theme.buttonTextStyle.copyWith(fontSize: 18 * theme.fontScale),
                ),
                subtitle: Text(
                  {
                    'softFemale': '부드러운 여성음 (기본)',
                    'deepMale': '낮고 차분한 남성음',
                    'assistantTone': 'AI 어시스턴트 톤',
                    'robotic': '기계적 음성'
                  }[_selectedTtsProfile]!,
                  style: theme.subtitleTextStyle,
                ),
                trailing: DropdownButton<String>(
                  value: _selectedTtsProfile,
                  dropdownColor: theme.isHighContrastEnabled ? Colors.black87 : Colors.white,
                  items: const [
                    DropdownMenuItem(value: 'softFemale', child: Text("부드러운 여성음")),
                    DropdownMenuItem(value: 'deepMale', child: Text("낮은 남성음")),
                    DropdownMenuItem(value: 'assistantTone', child: Text("AI 어시스턴트")),
                    DropdownMenuItem(value: 'robotic', child: Text("로봇음성")),
                  ],
                  onChanged: _onTtsProfileChanged,
                ),
              ),
              const Divider(),

              // 🔠 글자 크기
              ListTile(
                title: Text(
                  "글자 크기",
                  style: theme.buttonTextStyle.copyWith(fontSize: 18 * theme.fontScale),
                ),
                subtitle: Text(
                  theme.fontScale == 0.9
                      ? "작게"
                      : theme.fontScale == 1.0
                          ? "보통"
                          : "크게",
                  style: theme.subtitleTextStyle,
                ),
                trailing: DropdownButton<double>(
                  value: theme.fontScale,
                  dropdownColor: theme.isHighContrastEnabled ? Colors.black87 : Colors.white,
                  items: const [
                    DropdownMenuItem(value: 0.9, child: Text("작게")),
                    DropdownMenuItem(value: 1.0, child: Text("보통")),
                    DropdownMenuItem(value: 1.2, child: Text("크게")),
                  ],
                  onChanged: (value) {
                    if (value != null) theme.updateFontScale(value);
                  },
                ),
              ),
              const Divider(),

              // ⚫ 고대비 모드
              SwitchListTile(
                title: Text(
                  "고대비 모드",
                  style: theme.buttonTextStyle.copyWith(fontSize: 18 * theme.fontScale),
                ),
                subtitle: Text(
                  "배경을 어둡게, 글씨를 밝게 표시하여 시인성을 높입니다.",
                  style: theme.subtitleTextStyle,
                ),
                value: theme.isHighContrastEnabled,
                onChanged: (v) => theme.updateHighContrast(v),
                activeColor: Colors.tealAccent,
              ),

              const SizedBox(height: 20),

              // 🔊 미리듣기 버튼
              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _ttsProfiles.speak("이 음성은 현재 설정된 프로필의 미리듣기입니다.");
                  },
                  icon: const Icon(Icons.volume_up),
                  label: const Text("현재 음성 미리듣기"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}