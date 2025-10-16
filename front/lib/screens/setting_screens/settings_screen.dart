import 'package:flutter/material.dart';
import '../../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _ttsEnabled = true;
  bool _highContrast = false;
  double _fontScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _ttsEnabled = await SettingsService.isVoiceGuideEnabled();
    _fontScale = await SettingsService.getFontScale();
    _highContrast = await SettingsService.isHighContrastEnabled();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _highContrast ? Colors.black : Colors.amber[700];
    final textColor = _highContrast ? Colors.yellowAccent : Colors.black;

    return Scaffold(
      backgroundColor: _highContrast ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: themeColor,
        title: Text(
          "설정",
          style: TextStyle(color: textColor),
        ),
        iconTheme: IconThemeData(color: textColor),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 🎙 음성 안내 설정
          SwitchListTile(
            title: Text(
              "음성 안내 사용",
              style: TextStyle(
                fontSize: 18 * _fontScale,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              "시각장애인을 위한 안내 음성을 켜거나 끕니다.",
              style: TextStyle(fontSize: 14 * _fontScale, color: textColor.withOpacity(0.7)),
            ),
            value: _ttsEnabled,
            onChanged: (v) async {
              setState(() => _ttsEnabled = v);
              await SettingsService.setVoiceGuideEnabled(v);
            },
            activeColor: Colors.greenAccent,
          ),
          const Divider(),

          // 🔠 글자 크기 조정
          ListTile(
            title: Text(
              "글자 크기 조정",
              style: TextStyle(
                fontSize: 18 * _fontScale,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              _fontScale == 0.9
                  ? "작게"
                  : _fontScale == 1.0
                      ? "보통"
                      : "크게",
              style: TextStyle(fontSize: 14 * _fontScale, color: textColor.withOpacity(0.7)),
            ),
            trailing: DropdownButton<double>(
              value: _fontScale,
              dropdownColor: _highContrast ? Colors.black87 : Colors.white,
              items: const [
                DropdownMenuItem(value: 0.9, child: Text("작게")),
                DropdownMenuItem(value: 1.0, child: Text("보통")),
                DropdownMenuItem(value: 1.2, child: Text("크게")),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _fontScale = value);
                await SettingsService.setFontScale(value);
              },
            ),
          ),
          const Divider(),

          // ⚫ 고대비 모드
          SwitchListTile(
            title: Text(
              "고대비 모드",
              style: TextStyle(
                fontSize: 18 * _fontScale,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              "배경을 어둡게, 글씨를 밝게 표시하여 시인성을 높입니다.",
              style: TextStyle(fontSize: 14 * _fontScale, color: textColor.withOpacity(0.7)),
            ),
            value: _highContrast,
            onChanged: (v) async {
              setState(() => _highContrast = v);
              await SettingsService.setHighContrastEnabled(v);
            },
            activeColor: Colors.greenAccent,
          ),
        ],
      ),
    );
  }
}