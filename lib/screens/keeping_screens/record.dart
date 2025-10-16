

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

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
    _announceRecordCount();
  }

  Future<void> _announceRecordCount() async {
    await tts.speak("총 ${records.length}개의 검색 이력이 있습니다.");
  }

  Future<void> _speakDrugInfo(Map<String, String> record) async {
    final msg = "${record['drug']} 약품. ${record['method']}으로 검색됨. ${record['date']}에 검색.";
    await tts.speak(msg);
  }

  void _deleteAllRecords() async {
    if (records.isNotEmpty) {
      Vibration.vibrate(duration: 200);
      setState(() => records.clear());
      await tts.speak("검색 이력이 모두 삭제되었습니다.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      background: Colors.black,
      primary: Color(0xFFFFEB3B),
      onPrimary: Colors.black,
    );

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: const Text('검색 이력'),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: '모두 삭제',
            onPressed: _deleteAllRecords,
          ),
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Semantics(
                label: '검색 이력이 없습니다.',
                child: Text(
                  '검색 이력이 없습니다.',
                  style: TextStyle(color: scheme.primary, fontSize: 20),
                ),
              ),
            )
          : ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return Semantics(
                  button: true,
                  label:
                      '${record['drug']}, ${record['method']}으로 검색됨, ${record['date']}',
                  hint: '두 번 탭하면 약 정보로 이동',
                  child: Card(
                    color: Colors.grey[900],
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: scheme.primary, width: 1.5),
                    ),
                    child: ListTile(
                      onTap: () {
                        Vibration.vibrate(duration: 100);
                        _speakDrugInfo(record);
                        // TODO: 상세 페이지 이동 (약 정보 페이지 연결)
                      },
                      title: Text(
                        record['drug'] ?? '',
                        style: TextStyle(
                            color: scheme.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${record['method']} • ${record['date']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                    ),
                  ),
                );
              },
            ),
    );
  }
}