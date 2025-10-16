import 'package:flutter/material.dart';
import 'camera.dart'; // 카메라 촬영 페이지
import 'gallery.dart'; // 갤러리 업로드 페이지

class UploadPageScreen extends StatefulWidget {
  const UploadPageScreen({Key? key}) : super(key: key);

  @override
  State<UploadPageScreen> createState() => _UploadPageScreenState();
}

class _UploadPageScreenState extends State<UploadPageScreen> {
  void _navigateToPage(String option) {
    Widget targetPage;

    if (option == 'camera') {
      targetPage = const PrescriptionCameraPage();
    } else {
      targetPage = const PrescriptionUploadPage();
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => targetPage),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: const Text('처방전 업로드'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: '카메라로 촬영하기 버튼',
              button: true,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: const Text(
                  '카메라로 촬영하기',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _navigateToPage('camera'),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: '갤러리에서 선택하기 버튼',
              button: true,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text(
                  '갤러리에서 선택하기',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _navigateToPage('gallery'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}