import 'package:flutter/material.dart';
import 'package:pillypilly_h/screens/keeping_screens/record.dart';

class KeepingScreen extends StatefulWidget {
  const KeepingScreen({Key? key}) : super(key: key);

  @override
  State<KeepingScreen> createState() => _KeepingScreenState();
}

class _KeepingScreenState extends State<KeepingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 접근성용 제목
        title: Semantics(
          label: '보관함 화면 제목',
          child: const Text(
            '보관함',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Semantics(
              label: '검색 기록 확인하기 버튼 영역',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.history, size: 28),
                label: const Text(
                  '검색 기록 확인하기',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow, // 명도 대비 확보
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  minimumSize: const Size(200, 60), // 터치 영역 44px 이상 확보
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 3,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RecordScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}