import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
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
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '처방전 업로드',
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AccessibleButton(
                  label: '카메라로 촬영하기',
                  icon: Icons.photo_camera,
                  hint: '카메라를 사용해 처방전을 촬영합니다',
                  onPressed: () => _navigateToPage('camera'),
                ),
                const SizedBox(height: 20),
                AccessibleButton(
                  label: '갤러리에서 선택하기',
                  icon: Icons.photo_library,
                  hint: '갤러리에서 처방전 이미지를 선택합니다',
                  onPressed: () => _navigateToPage('gallery'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}