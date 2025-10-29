import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import 'box_qr.dart';
import 'box_ocr.dart';

class BoxScreen extends StatefulWidget {
  const BoxScreen({Key? key}) : super(key: key);

  @override
  State<BoxScreen> createState() => _BoxScreenState();
}

class _BoxScreenState extends State<BoxScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        final double fontScale = theme.fontScale;
        final bool isContrast = theme.isHighContrast;

        // 고대비 모드 색상
        final Color bgColor = isContrast ? Colors.black : Colors.white;
        final Color textColor = isContrast ? Colors.yellowAccent : Colors.black;
        final Color buttonColor = isContrast ? Colors.amberAccent : Colors.blue;

        return AccessibleScaffold(
          title: '약 상자 인식',
          backgroundColor: bgColor,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ 바코드/QR 버튼
                  AccessibleButton(
                    label: '바코드 / QR 찍기',
                    icon: Icons.qr_code_scanner,
                    hint: '바코드나 QR 코드를 스캔합니다',
                    width: double.infinity,
                    height: 70,
                    backgroundColor: buttonColor,
                    textStyle: TextStyle(
                      fontSize: 20 * fontScale,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BoxQrScreen()),
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  // ✅ OCR 텍스트 인식 버튼
                  AccessibleButton(
                    label: '텍스트 (OCR) 인식',
                    icon: Icons.text_fields,
                    hint: '약 상자의 텍스트를 인식합니다',
                    width: double.infinity,
                    height: 70,
                    backgroundColor: buttonColor,
                    textStyle: TextStyle(
                      fontSize: 20 * fontScale,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BoxOcrScreen()),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // 💡 음성안내 및 접근성 보조 텍스트
                  Text(
                    '카메라를 약 상자에 가까이 가져가면 자동으로 인식됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16 * fontScale,
                      color: isContrast ? Colors.yellow : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}