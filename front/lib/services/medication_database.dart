import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class MedicationDatabase {
  static final MedicationDatabase _instance = MedicationDatabase._internal();
  factory MedicationDatabase() => _instance;
  MedicationDatabase._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'medication.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 복약 일정 테이블
    await db.execute('''
      CREATE TABLE medication_schedules(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        drug_name TEXT NOT NULL,
        dosage TEXT NOT NULL,
        times_per_day INTEGER NOT NULL,
        times TEXT NOT NULL, -- JSON 배열로 저장 (예: ["08:00", "13:00", "18:00"])
        days_of_week TEXT NOT NULL, -- JSON 배열로 저장 (예: [1,2,3,4,5,6,7])
        start_date TEXT NOT NULL,
        end_date TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');

    // 복약 기록 테이블
    await db.execute('''
      CREATE TABLE medication_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        schedule_id INTEGER NOT NULL,
        taken_date TEXT NOT NULL,
        taken_time TEXT NOT NULL,
        is_taken INTEGER NOT NULL DEFAULT 0,
        taken_at TEXT,
        notes TEXT,
        FOREIGN KEY (schedule_id) REFERENCES medication_schedules (id)
      )
    ''');

    // 주간 리셋 기록 테이블
    await db.execute('''
      CREATE TABLE weekly_resets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        week_start_date TEXT NOT NULL,
        reset_date TEXT NOT NULL,
        is_reset INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // 복약 일정 추가
  Future<int> insertMedicationSchedule(MedicationSchedule schedule) async {
    final db = await database;
    return await db.insert('medication_schedules', schedule.toMap());
  }

  // 복약 일정 조회
  Future<List<MedicationSchedule>> getMedicationSchedules() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'medication_schedules',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => MedicationSchedule.fromMap(maps[i]));
  }

  // 오늘의 복약 일정 조회
  Future<List<MedicationSchedule>> getTodaySchedules() async {
    final db = await database;
    final today = DateTime.now();
    final dayOfWeek = today.weekday;
    
    final List<Map<String, dynamic>> maps = await db.query(
      'medication_schedules',
      where: 'is_active = ? AND days_of_week LIKE ?',
      whereArgs: [1, '%$dayOfWeek%'],
    );
    return List.generate(maps.length, (i) => MedicationSchedule.fromMap(maps[i]));
  }

  // 복약 기록 추가
  Future<int> insertMedicationRecord(MedicationRecord record) async {
    final db = await database;
    return await db.insert('medication_records', record.toMap());
  }

  // 오늘의 복약 기록 조회
  Future<List<MedicationRecord>> getTodayRecords() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    final List<Map<String, dynamic>> maps = await db.query(
      'medication_records',
      where: 'taken_date = ?',
      whereArgs: [today],
    );
    return List.generate(maps.length, (i) => MedicationRecord.fromMap(maps[i]));
  }

  // 복약 기록 업데이트
  Future<int> updateMedicationRecord(int recordId, bool isTaken, {String? notes}) async {
    final db = await database;
    return await db.update(
      'medication_records',
      {
        'is_taken': isTaken ? 1 : 0,
        'taken_at': isTaken ? DateTime.now().toIso8601String() : null,
        'notes': notes,
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  // 주간 리셋 확인 및 실행
  Future<void> checkAndResetWeekly() async {
    final db = await database;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartStr = weekStart.toIso8601String().split('T')[0];

    // 이번 주 리셋 여부 확인
    final List<Map<String, dynamic>> maps = await db.query(
      'weekly_resets',
      where: 'week_start_date = ?',
      whereArgs: [weekStartStr],
    );

    if (maps.isEmpty) {
      // 이번 주 리셋이 안되었으면 실행
      await _resetWeeklyRecords();
      
      // 리셋 기록 추가
      await db.insert('weekly_resets', {
        'week_start_date': weekStartStr,
        'reset_date': now.toIso8601String(),
        'is_reset': 1,
      });
    }
  }

  // 주간 복약 기록 리셋
  Future<void> _resetWeeklyRecords() async {
    final db = await database;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(Duration(days: 6));
    
    // 이번 주의 모든 복약 기록을 미복용으로 리셋
    await db.update(
      'medication_records',
      {
        'is_taken': 0,
        'taken_at': null,
      },
      where: 'taken_date >= ? AND taken_date <= ?',
      whereArgs: [
        weekStart.toIso8601String().split('T')[0],
        weekEnd.toIso8601String().split('T')[0],
      ],
    );
  }

  // 복약 일정 삭제
  Future<int> deleteMedicationSchedule(int id) async {
    final db = await database;
    return await db.update(
      'medication_schedules',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 데이터베이스 닫기
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

class MedicationSchedule {
  final int? id;
  final String drugName;
  final String dosage;
  final int timesPerDay;
  final List<String> times;
  final List<int> daysOfWeek;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
  final DateTime createdAt;

  MedicationSchedule({
    this.id,
    required this.drugName,
    required this.dosage,
    required this.timesPerDay,
    required this.times,
    required this.daysOfWeek,
    required this.startDate,
    this.endDate,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'drug_name': drugName,
      'dosage': dosage,
      'times_per_day': timesPerDay,
      'times': jsonEncode(times),
      'days_of_week': jsonEncode(daysOfWeek),
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory MedicationSchedule.fromMap(Map<String, dynamic> map) {
    return MedicationSchedule(
      id: map['id'],
      drugName: map['drug_name'],
      dosage: map['dosage'],
      timesPerDay: map['times_per_day'],
      times: List<String>.from(jsonDecode(map['times'])),
      daysOfWeek: List<int>.from(jsonDecode(map['days_of_week'])),
      startDate: DateTime.parse(map['start_date']),
      endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
      isActive: map['is_active'] == 1,
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

class MedicationRecord {
  final int? id;
  final int scheduleId;
  final String takenDate;
  final String takenTime;
  final bool isTaken;
  final String? takenAt;
  final String? notes;

  MedicationRecord({
    this.id,
    required this.scheduleId,
    required this.takenDate,
    required this.takenTime,
    this.isTaken = false,
    this.takenAt,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'schedule_id': scheduleId,
      'taken_date': takenDate,
      'taken_time': takenTime,
      'is_taken': isTaken ? 1 : 0,
      'taken_at': takenAt,
      'notes': notes,
    };
  }

  factory MedicationRecord.fromMap(Map<String, dynamic> map) {
    return MedicationRecord(
      id: map['id'],
      scheduleId: map['schedule_id'],
      takenDate: map['taken_date'],
      takenTime: map['taken_time'],
      isTaken: map['is_taken'] == 1,
      takenAt: map['taken_at'],
      notes: map['notes'],
    );
  }
}
