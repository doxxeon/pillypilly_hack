import 'package:flutter/material.dart';
import 'package:pillypilly_h/screens/search_screens/search_screen.dart';
import 'package:pillypilly_h/screens/upload_page_screens/upload_page_screen.dart';
import 'package:pillypilly_h/screens/box_screens/box_screen.dart';
import 'package:pillypilly_h/screens/manage_screens/manage_screen.dart';
import 'package:pillypilly_h/screens/safety_screens/safety_screen.dart';
import 'package:pillypilly_h/screens/keeping_screens/keeping_screen.dart';
import 'package:pillypilly_h/screens/setting_screens/settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final List<_Feature> features = [
    _Feature(title: '알약 검색하기', options: ['음성으로 검색하기', '텍스트로 검색하기', '카메라로 촬영하기'], icon: Icons.search),
    _Feature(title: '처방전 업로드', options: ['카메라로 촬영하기', '갤러리에서 선택하기'], icon: Icons.upload_file),
    _Feature(title: '약 상자 인식', options: ['바코드/QR 찍기'], icon: Icons.qr_code_scanner),
    _Feature(title: '복약 관리', options: ['복용 일정 알림', '복약 여부 체크'], icon: Icons.check_circle),
    _Feature(title: '약물 안전성 검사', options: ['병용금기 확인하기'], icon: Icons.health_and_safety),
    _Feature(title: '보관함', options: ['검색 기록 확인하기'], icon: Icons.folder),
    _Feature(title: '설정', options: ['음성 안내 설정', '글자 크기 조정', '고대비 모드'], icon: Icons.settings),
  ];

  void _showOptions(BuildContext context, _Feature feature) {
    if (feature.title == "설정") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    if (feature.title == "알약 검색하기") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen()));
      return;
    }
    if (feature.title == "처방전 업로드") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => UploadPageScreen()));
      return;
    }
    if (feature.title == "약 상자 인식") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => BoxScreen()));
      return;
    }
    if (feature.title == "복약 관리") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ManageScreen()));
      return;
    }
    if (feature.title == "약물 안전성 검사") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SafetyScreen()));
      return;
    }
    if (feature.title == "보관함") {
      Navigator.push(context, MaterialPageRoute(builder: (_) => KeepingScreen()));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.amber[700],
        centerTitle: true,
        title: const Text(
          'Pillypilly',
          style: TextStyle(color: Colors.black, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            for (int i = 0; i < features.length; i++) ...[
              Semantics(
                label: '${features[i].title} 실행 버튼',
                child: ElevatedButton.icon(
                  icon: Icon(features[i].icon),
                  label: Text(
                    features[i].title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(80),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _showOptions(context, features[i]),
                ),
              ),
              if (i != features.length - 1) const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _Feature {
  final String title;
  final List<String> options;
  final IconData icon;

  _Feature({required this.title, required this.options, required this.icon});
}

class PlaceholderPage extends StatelessWidget {
  final String title;

  const PlaceholderPage({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
