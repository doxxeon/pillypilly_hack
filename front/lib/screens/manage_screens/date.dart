import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../services/medication_database.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import '../../widgets/loading_widget.dart';

class DateScreen extends StatefulWidget {
  const DateScreen({super.key});

  @override
  State<DateScreen> createState() => _DateScreenState();
}

class _DateScreenState extends State<DateScreen> {
  final FlutterTts tts = FlutterTts();
  final MedicationDatabase _db = MedicationDatabase();
  List<MedicationSchedule> schedules = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    _checkWeeklyReset();
  }

  Future<void> _loadSchedules() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loadedSchedules = await _db.getMedicationSchedules();
      setState(() {
        schedules = loadedSchedules;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "복약 일정을 불러오는데 실패했습니다.";
        _isLoading = false;
      });
    }
  }

  Future<void> _checkWeeklyReset() async {
    try {
      await _db.checkAndResetWeekly();
    } catch (e) {
      debugPrint("주간 리셋 확인 중 오류: $e");
    }
  }

  Future<void> _addSchedule(ThemeService theme) async {
    String drugName = '';
    String dosage = '';
    List<String> times = ['09:00'];
    List<int> selectedDays = [1]; // 월요일부터 시작

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: theme.backgroundColor,
              title: Text(
                '복약 일정 추가',
                style: theme.titleStyle.copyWith(fontSize: 20 * theme.fontScale),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: '약 이름 입력창',
                      hint: '약의 이름을 입력하세요.',
                      textField: true,
                      child: TextField(
                        style: theme.bodyTextStyle,
                        decoration: InputDecoration(
                          labelText: '약 이름',
                          labelStyle: theme.subtitleTextStyle,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: theme.primaryColor),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: theme.primaryColor),
                          ),
                        ),
                        onTap: () {
                          if (theme.isVoiceGuideEnabled) {
                            tts.speak("약의 이름을 입력하세요.");
                          }
                        },
                        onChanged: (value) => drugName = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: '복용량 입력창',
                      hint: '복용량을 입력하세요.',
                      textField: true,
                      child: TextField(
                        style: theme.bodyTextStyle,
                        decoration: InputDecoration(
                          labelText: '복용량 (예: 1정, 2캡슐)',
                          labelStyle: theme.subtitleTextStyle,
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: theme.primaryColor),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: theme.primaryColor),
                          ),
                        ),
                        onChanged: (value) => dosage = value,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '복용 요일 선택',
                      style: theme.buttonTextStyle.copyWith(fontSize: 16 * theme.fontScale),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: List.generate(7, (index) {
                        final dayNames = ['월', '화', '수', '목', '금', '토', '일'];
                        final isSelected = selectedDays.contains(index + 1);
                        return Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: FilterChip(
                            label: Text(dayNames[index]),
                            selected: isSelected,
                            onSelected: (selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedDays.add(index + 1);
                                } else {
                                  selectedDays.remove(index + 1);
                                }
                              });
                            },
                            selectedColor: theme.primaryColor,
                            checkmarkColor: theme.buttonTextColor,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '복용 시간',
                      style: theme.buttonTextStyle.copyWith(fontSize: 16 * theme.fontScale),
                    ),
                    const SizedBox(height: 8),
                    ...times.asMap().entries.map((entry) {
                      int index = entry.key;
                      String time = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${index + 1}회차: $time',
                                style: theme.bodyTextStyle,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.access_time, color: theme.primaryColor),
                              onPressed: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    times[index] = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                  });
                                }
                              },
                            ),
                            if (times.length > 1)
                              IconButton(
                                icon: Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () {
                                  setDialogState(() {
                                    times.removeAt(index);
                                  });
                                },
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    if (times.length < 5)
                      TextButton.icon(
                        icon: Icon(Icons.add, color: theme.primaryColor),
                        label: Text('시간 추가', style: TextStyle(color: theme.primaryColor)),
                        onPressed: () {
                          setDialogState(() {
                            times.add('09:00');
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('취소', style: TextStyle(color: theme.textColor)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (drugName.isNotEmpty && dosage.isNotEmpty && selectedDays.isNotEmpty) {
                      final schedule = MedicationSchedule(
                        drugName: drugName,
                        dosage: dosage,
                        timesPerDay: times.length,
                        times: times,
                        daysOfWeek: selectedDays,
                        startDate: DateTime.now(),
                        createdAt: DateTime.now(),
                      );
                      
                      try {
                        await _db.insertMedicationSchedule(schedule);
                        await _loadSchedules();
                        Navigator.of(context).pop();
                        if (theme.isVoiceGuideEnabled) {
                          await tts.speak("복약 일정이 추가되었습니다.");
                        }
                        Vibration.vibrate(duration: 200);
                      } catch (e) {
                        if (theme.isVoiceGuideEnabled) {
                          await tts.speak("복약 일정 추가에 실패했습니다.");
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.buttonTextColor,
                  ),
                  child: Text('추가'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteSchedule(int id, ThemeService theme) async {
    try {
      await _db.deleteMedicationSchedule(id);
      await _loadSchedules();
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("복약 일정이 삭제되었습니다.");
      }
      Vibration.vibrate(duration: 150);
    } catch (e) {
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("복약 일정 삭제에 실패했습니다.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '복용 일정 알림',
          body: _isLoading
              ? const LoadingWidget(message: "복약 일정을 불러오는 중입니다...")
              : _errorMessage != null
                  ? CustomErrorWidget(
                      message: _errorMessage!,
                      onRetry: () => _loadSchedules(),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: AccessibleButton(
                            label: '새 복약 일정 추가',
                            icon: Icons.add,
                            hint: '새로운 복약 일정을 추가합니다',
                            onPressed: () => _addSchedule(theme),
                          ),
                        ),
                        Expanded(
                          child: schedules.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.medication,
                                        size: 64,
                                        color: theme.textColor.withOpacity(0.5),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        '등록된 복약 일정이 없습니다',
                                        style: theme.bodyTextStyle.copyWith(
                                          fontSize: 18 * theme.fontScale,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '새 복약 일정 추가 버튼을 눌러 일정을 등록하세요',
                                        style: theme.subtitleTextStyle,
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16.0),
                                  itemCount: schedules.length,
                                  itemBuilder: (context, index) {
                                    final schedule = schedules[index];
                                    return Card(
                                      color: theme.buttonColor,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        title: Text(
                                          schedule.drugName,
                                          style: theme.buttonTextStyle.copyWith(
                                            fontSize: 18 * theme.fontScale,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '복용량: ${schedule.dosage}',
                                              style: theme.bodyTextStyle.copyWith(
                                                fontSize: 14 * theme.fontScale,
                                                color: theme.buttonTextColor,
                                              ),
                                            ),
                                            Text(
                                              '횟수: ${schedule.timesPerDay}회/일',
                                              style: theme.bodyTextStyle.copyWith(
                                                fontSize: 14 * theme.fontScale,
                                                color: theme.buttonTextColor,
                                              ),
                                            ),
                                            Text(
                                              '시간: ${schedule.times.join(', ')}',
                                              style: theme.bodyTextStyle.copyWith(
                                                fontSize: 14 * theme.fontScale,
                                                color: theme.buttonTextColor,
                                              ),
                                            ),
                                            Text(
                                              '요일: ${_getDayNames(schedule.daysOfWeek)}',
                                              style: theme.bodyTextStyle.copyWith(
                                                fontSize: 14 * theme.fontScale,
                                                color: theme.buttonTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: IconButton(
                                          icon: Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _deleteSchedule(schedule.id!, theme),
                                        ),
                                      ),
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

  String _getDayNames(List<int> days) {
    final dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    return days.map((day) => dayNames[day - 1]).join(', ');
  }
}