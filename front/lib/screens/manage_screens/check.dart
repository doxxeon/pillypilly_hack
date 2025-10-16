import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});

  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> {
  final FlutterTts tts = FlutterTts();
  Map<String, List<Map<String, dynamic>>> weeklySchedules = {
    '월요일': [],
    '화요일': [],
    '수요일': [],
    '목요일': [],
    '금요일': [],
    '토요일': [],
    '일요일': [],
  };

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('schedules');
    if (savedData != null) {
      final List<Map<String, dynamic>> schedules =
          List<Map<String, dynamic>>.from(json.decode(savedData));

      // 요일별 그룹화
      final Map<String, List<Map<String, dynamic>>> grouped = {
        '월요일': [],
        '화요일': [],
        '수요일': [],
        '목요일': [],
        '금요일': [],
        '토요일': [],
        '일요일': [],
      };

      for (var item in schedules) {
        final day = item['day'] ?? '월요일';
        grouped[day]?.add(item);
      }

      setState(() {
        weeklySchedules = grouped;
      });

      await tts.speak("복약 여부 확인 페이지입니다. 요일별 복용 일정을 불러왔습니다.");
    } else {
      await tts.speak("저장된 복약 일정이 없습니다. 복약 일정 관리 페이지에서 추가해주세요.");
    }
  }

  Future<void> _toggleTaken(String day, int index) async {
    setState(() {
      weeklySchedules[day]![index]['taken'] =
          !weeklySchedules[day]![index]['taken'];
    });

    // 저장된 데이터도 업데이트
    final prefs = await SharedPreferences.getInstance();
    final allData = weeklySchedules.values.expand((v) => v).toList();
    await prefs.setString('schedules', json.encode(allData));

    final record = weeklySchedules[day]![index];
    final msg = record['taken']
        ? "${record['day']}의 ${record['drug']} 복용 완료로 표시되었습니다."
        : "${record['day']}의 ${record['drug']} 복용 미완료로 변경되었습니다.";
    await tts.speak(msg);
    Vibration.vibrate(duration: 120);
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
        title: const Text('복약 여부 체크'),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: ListView(
        children: weeklySchedules.entries.map((entry) {
          final day = entry.key;
          final schedules = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: TextStyle(
                      color: scheme.primary,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                schedules.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Text('등록된 복약 일정이 없습니다.',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 15)),
                      )
                    : Column(
                        children: schedules.asMap().entries.map((e) {
                          final index = e.key;
                          final record = e.value;
                          return Semantics(
                            button: true,
                            label:
                                '${record['drug']} ${record['time']}에 복용 예정. 현재 상태: ${record['taken'] ? "복용 완료" : "미복용"}',
                            hint: '두 번 탭하여 복용 상태를 변경합니다.',
                            child: Card(
                              color: Colors.grey[900],
                              margin:
                                  const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: scheme.primary, width: 1.5),
                              ),
                              child: ListTile(
                                onTap: () => _toggleTaken(day, index),
                                leading: Icon(
                                  record['taken']
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: record['taken']
                                      ? Colors.greenAccent
                                      : scheme.primary,
                                  size: 28,
                                ),
                                title: Text(
                                  record['drug'],
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '시간: ${record['time']}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                                trailing: Text(
                                  record['taken'] ? '완료' : '미완료',
                                  style: TextStyle(
                                    color: record['taken']
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                const Divider(color: Colors.white24, height: 24),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}