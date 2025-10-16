import 'package:flutter/material.dart';
import 'package:pillypilly_h/screens/manage_screens/date.dart';
import 'package:pillypilly_h/screens/manage_screens/check.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({Key? key}) : super(key: key);

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          label: '복약 관리 화면',
          child: Text('복약 관리'),
        ),
        backgroundColor: Colors.yellow[700],
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              onTapHint: '복용 일정 알림 화면으로 이동',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.alarm, size: 36),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    '복용 일정 알림',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DateScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(200, 64),
                  backgroundColor: Colors.yellow[700],
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Semantics(
              button: true,
              onTapHint: '복약 여부 체크 화면으로 이동',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 36),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    '복약 여부 체크',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CheckScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(200, 64),
                  backgroundColor: Colors.yellow[700],
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontSize: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}