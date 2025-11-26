import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final FlutterTts tts = FlutterTts();

  // 임시 데이터 (DB 연결 전까지)
  final List<Map<String, String>> records = [
    {
      'drug': '타이레놀정 500mg',
      'method': 'OCR 인식',
      'date': '2025-10-13',
    },
    {
      'drug': '게보린정',
      'method': '바코드 스캔',
      'date': '2025-10-12',
    },
    {
      'drug': '오트리빈비강스프레이',
      'method': '텍스트 검색',
      'date': '2025-10-11',
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final theme = context.read<ThemeService>();
      _announceRecordCount(theme);
    });
  }

  Future<void> _announceRecordCount(ThemeService theme) async {
    if (theme.isVoiceGuideEnabled) {
    await tts.speak("총 ${records.length}개의 검색 이력이 있습니다.");
    }
  }

  Future<void> _speakDrugInfo(Map<String, String> record, ThemeService theme) async {
    if (theme.isVoiceGuideEnabled) {
    final msg = "${record['drug']} 약품. ${record['method']}으로 검색됨. ${record['date']}에 검색.";
    await tts.speak(msg);
    }
  }

  void _deleteAllRecords(ThemeService theme) async {
    if (records.isNotEmpty) {
      Vibration.vibrate(duration: 200);
      setState(() => records.clear());
      if (theme.isVoiceGuideEnabled) {
      await tts.speak("검색 이력이 모두 삭제되었습니다.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '검색 이력',
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: '모두 삭제',
              onPressed: () => _deleteAllRecords(theme),
          ),
        ],
      body: records.isEmpty
          ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: theme.textColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                  '검색 이력이 없습니다.',
                        style: theme.bodyTextStyle.copyWith(
                          fontSize: 20 * theme.fontScale,
                ),
                      ),
                    ],
              ),
            )
          : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                    return Card(
                      color: theme.buttonColor,
                      margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                          record['drug']!,
                          style: theme.buttonTextStyle.copyWith(
                            fontSize: 18 * theme.fontScale,
                          ),
                      ),
                      subtitle: Text(
                        '${record['method']} • ${record['date']}',
                          style: theme.bodyTextStyle.copyWith(
                            fontSize: 14 * theme.fontScale,
                            color: theme.buttonTextColor.withOpacity(0.7),
                          ),
                    ),
                        onTap: () {
                          Vibration.vibrate(duration: 100);
                          _speakDrugInfo(record, theme);
                        },
                  ),
                );
              },
            ),
        );
      },
    );
  }
}