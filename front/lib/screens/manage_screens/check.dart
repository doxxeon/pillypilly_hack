import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../services/medication_database.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import '../../widgets/loading_widget.dart';

class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});

  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> {
  final FlutterTts tts = FlutterTts();
  final MedicationDatabase _db = MedicationDatabase();
  List<MedicationSchedule> todaySchedules = [];
  List<MedicationRecord> todayRecords = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTodayData();
  }

  Future<void> _loadTodayData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 주간 리셋 확인
      await _db.checkAndResetWeekly();
      
      // 오늘의 복약 일정과 기록 로드
      final schedules = await _db.getTodaySchedules();
      final records = await _db.getTodayRecords();
      
      setState(() {
        todaySchedules = schedules;
        todayRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "오늘의 복약 정보를 불러오는데 실패했습니다.";
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleMedicationTaken(MedicationSchedule schedule, String time, ThemeService theme) async {
    try {
      // 해당 시간의 기록 찾기
      final existingRecord = todayRecords.firstWhere(
        (record) => record.scheduleId == schedule.id && record.takenTime == time,
        orElse: () => MedicationRecord(
          scheduleId: schedule.id!,
          takenDate: DateTime.now().toIso8601String().split('T')[0],
          takenTime: time,
        ),
      );

      final isTaken = !existingRecord.isTaken;
      
      if (existingRecord.id == null) {
        // 새 기록 생성
        final newRecord = MedicationRecord(
          scheduleId: schedule.id!,
          takenDate: DateTime.now().toIso8601String().split('T')[0],
          takenTime: time,
          isTaken: isTaken,
          takenAt: isTaken ? DateTime.now().toIso8601String() : null,
        );
        await _db.insertMedicationRecord(newRecord);
      } else {
        // 기존 기록 업데이트
        await _db.updateMedicationRecord(existingRecord.id!, isTaken);
      }

      // 데이터 새로고침
      await _loadTodayData();
      
      if (theme.isVoiceGuideEnabled) {
        await tts.speak(isTaken ? "복용 완료로 기록되었습니다." : "복용 기록이 취소되었습니다.");
      }
      Vibration.vibrate(duration: 150);
    } catch (e) {
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("복용 기록 업데이트에 실패했습니다.");
      }
    }
  }

  bool _isMedicationTaken(MedicationSchedule schedule, String time) {
    return todayRecords.any((record) => 
      record.scheduleId == schedule.id && 
      record.takenTime == time && 
      record.isTaken
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '복약 여부 체크',
          body: _isLoading
              ? const LoadingWidget(message: "오늘의 복약 정보를 불러오는 중입니다...")
              : _errorMessage != null
                  ? CustomErrorWidget(
                      message: _errorMessage!,
                      onRetry: () => _loadTodayData(),
                    )
                  : todaySchedules.isEmpty
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
                                '오늘은 복용할 약이 없습니다',
                                style: theme.bodyTextStyle.copyWith(
                                  fontSize: 18 * theme.fontScale,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '복약 일정을 먼저 등록해주세요',
                                style: theme.subtitleTextStyle,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                '오늘의 복약 일정',
                                style: theme.titleStyle.copyWith(
                                  fontSize: 20 * theme.fontScale,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16.0),
                                itemCount: todaySchedules.length,
                                itemBuilder: (context, index) {
                                  final schedule = todaySchedules[index];
                                  return Card(
                                    color: theme.buttonColor,
                                    margin: const EdgeInsets.only(bottom: 16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            schedule.drugName,
                                            style: theme.buttonTextStyle.copyWith(
                                              fontSize: 20 * theme.fontScale,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '복용량: ${schedule.dosage}',
                                            style: theme.bodyTextStyle.copyWith(
                                              fontSize: 16 * theme.fontScale,
                                              color: theme.buttonTextColor,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '복용 시간',
                                            style: theme.buttonTextStyle.copyWith(
                                              fontSize: 16 * theme.fontScale,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...schedule.times.map((time) {
                                            final isTaken = _isMedicationTaken(schedule, time);
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      time,
                                                      style: theme.bodyTextStyle.copyWith(
                                                        fontSize: 16 * theme.fontScale,
                                                        color: theme.buttonTextColor,
                                                      ),
                                                    ),
                                                  ),
                                                  Switch(
                                                    value: isTaken,
                                                    onChanged: (value) => _toggleMedicationTaken(schedule, time, theme),
                                                    activeColor: Colors.green,
                                                    inactiveThumbColor: Colors.grey,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Icon(
                                                    isTaken ? Icons.check_circle : Icons.radio_button_unchecked,
                                                    color: isTaken ? Colors.green : Colors.grey,
                                                    size: 24,
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: AccessibleButton(
                                label: '새로고침',
                                icon: Icons.refresh,
                                hint: '복약 정보를 새로고침합니다',
                                onPressed: () => _loadTodayData(),
                              ),
                            ),
                          ],
                        ),
        );
      },
    );
  }
}