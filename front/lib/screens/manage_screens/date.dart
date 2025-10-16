import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DateScreen extends StatefulWidget {
  const DateScreen({super.key});

  @override
  State<DateScreen> createState() => _DateScreenState();
}

class _DateScreenState extends State<DateScreen> {
  final FlutterTts tts = FlutterTts();
  List<Map<String, dynamic>> schedules = [];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final savedData = prefs.getString('schedules');
    if (savedData != null) {
      setState(() {
        schedules = List<Map<String, dynamic>>.from(json.decode(savedData));
      });
    } else {
      schedules = [
        {'drug': '타이레놀정 500mg', 'time': '09:00 AM', 'day': '월요일', 'taken': false},
        {'drug': '게보린정', 'time': '02:00 PM', 'day': '화요일', 'taken': true},
      ];
    }
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedules', json.encode(schedules));
  }

  Future<void> _addSchedule() async {
    String drugName = '';
    String selectedDay = '월요일';
    TimeOfDay? time;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text('복약 일정 추가', style: TextStyle(color: Colors.yellow)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: '약 이름 입력창',
                hint: '약의 이름을 입력하세요.',
                textField: true,
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '약 이름',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.yellow)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.yellow)),
                  ),
                  onTap: () => tts.speak("약의 이름을 입력하세요."),
                  onChanged: (value) => drugName = value,
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: '요일 선택',
                hint: '복용 요일을 선택하세요.',
                child: DropdownButton<String>(
                  value: selectedDay,
                  dropdownColor: Colors.black,
                  items: ['월요일','화요일','수요일','목요일','금요일','토요일','일요일']
                      .map((day) => DropdownMenuItem(
                            value: day,
                            child: Text(day,
                                style: const TextStyle(color: Colors.yellow)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    selectedDay = value!;
                    tts.speak("$selectedDay 선택됨");
                  },
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: '시간 선택 버튼',
                hint: '복용 시간을 선택합니다.',
                button: true,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time != null) {
                      final msg =
                          '${time!.hourOfPeriod.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')} ${time!.period == DayPeriod.am ? '오전' : '오후'} 선택됨';
                      await tts.speak(msg);
                    }
                  },
                  icon: const Icon(Icons.access_time, color: Colors.black),
                  label: const Text('시간 선택',
                      style: TextStyle(color: Colors.black, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow,
                    minimumSize: const Size(180, 44),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                tts.speak("일정 추가를 취소했습니다.");
                Navigator.pop(context);
              },
              child: const Text('취소', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () async {
                if (drugName.isNotEmpty && time != null) {
                  final formatted =
                      '${time!.hourOfPeriod.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')} ${time!.period == DayPeriod.am ? 'AM' : 'PM'}';
                  setState(() {
                    schedules.add({
                      'drug': drugName,
                      'time': formatted,
                      'day': selectedDay,
                      'taken': false,
                    });
                  });
                  await _saveSchedules();
                  Vibration.vibrate(duration: 150);
                  await tts.speak("$selectedDay, $drugName, $formatted 복약 일정이 추가되었습니다.");
                  Navigator.pop(context);
                } else {
                  await tts.speak("모든 정보를 입력해야 저장할 수 있습니다.");
                }
              },
              child: const Text('저장', style: TextStyle(color: Colors.yellow)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleTaken(int index) async {
    setState(() {
      schedules[index]['taken'] = !schedules[index]['taken'];
    });
    await _saveSchedules();
    final record = schedules[index];
    final message = record['taken']
        ? "${record['day']}의 ${record['drug']} 복약 완료로 표시되었습니다."
        : "${record['day']}의 ${record['drug']} 복약 미완료로 변경되었습니다.";
    await tts.speak(message);
    Vibration.vibrate(duration: 100);
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
        title: const Text('복약 일정 관리'),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: ListView.builder(
        itemCount: schedules.length,
        itemBuilder: (context, index) {
          final schedule = schedules[index];
          return Semantics(
            button: true,
            label:
                '${schedule['day']} ${schedule['drug']} ${schedule['time']}에 복용 예정. 현재 상태: ${schedule['taken'] ? "복용 완료" : "미복용"}',
            hint: '탭하여 복용 상태를 변경합니다.',
            child: Card(
              color: Colors.grey[900],
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.primary, width: 1.5),
              ),
              child: ListTile(
                onTap: () => _toggleTaken(index),
                leading: Icon(
                  schedule['taken']
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color:
                      schedule['taken'] ? Colors.greenAccent : scheme.primary,
                  size: 28,
                ),
                title: Text(
                  schedule['drug'],
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${schedule['day']} • 시간: ${schedule['time']}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                trailing: Text(
                  schedule['taken'] ? '완료' : '미완료',
                  style: TextStyle(
                    color: schedule['taken']
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),

      // ✅ 장애인 친화형 접근성 버튼으로 교체됨
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Semantics(
          label: '복약 일정 추가 버튼',
          hint: '한 번 탭하여 새 복약 일정을 등록합니다.',
          button: true,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 30, color: Colors.black),
            label: const Text(
              '복약 일정 추가',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.primary,
              minimumSize: const Size(double.infinity, 64),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 6,
            ),
            onPressed: () async {
              Vibration.vibrate(duration: 80);
              await tts.speak('새 복약 일정 추가 창이 열렸습니다.');
              await _addSchedule();
            },
          ),
        ),
      ),
    );
  }
}