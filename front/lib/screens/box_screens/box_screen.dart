import 'package:flutter/material.dart';
import 'package:pillypilly_h/screens/box_screens/box_qr.dart';
import 'package:pillypilly_h/screens/box_screens/box_ocr.dart';

class BoxScreen extends StatefulWidget {
  const BoxScreen({Key? key}) : super(key: key);

  @override
  State<BoxScreen> createState() => _BoxScreenState();
}

class _BoxScreenState extends State<BoxScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.yellow,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Semantics(
          label: '약 상자 인식 화면 제목',
          child: const Text(
            '약 상자 인식',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ),
        leading: Semantics(
          label: '뒤로 가기',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              button: true,
              label: '바코드 및 QR 코드 스캐너 실행 버튼',
              child: Tooltip(
                message: '바코드/QR 찍기',
                child: SizedBox(
                  width: 220,
                  height: 60,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner, size: 36, color: Colors.black),
                    label: const Text(
                      '바코드/QR 찍기',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellow,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      minimumSize: const Size(44, 44),
                      elevation: 3,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BoxQrScreen()),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Semantics(
              button: true,
              label: '약 상자 텍스트 OCR 인식 버튼',
              child: Tooltip(
                message: '텍스트(OCR) 인식하기',
                child: SizedBox(
                  width: 220,
                  height: 60,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.text_fields, size: 36, color: Colors.black),
                    label: const Text(
                      '텍스트(OCR) 인식',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellow,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      minimumSize: const Size(44, 44),
                      elevation: 3,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BoxOcrScreen()),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}