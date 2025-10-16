import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

class PrescriptionCameraPage extends StatefulWidget {
  const PrescriptionCameraPage({Key? key}) : super(key: key);

  @override
  State<PrescriptionCameraPage> createState() => _PrescriptionCameraPageState();
}

class _PrescriptionCameraPageState extends State<PrescriptionCameraPage> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();
  File? _capturedImage;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _speak("처방전 촬영 페이지입니다. 중앙의 큰 버튼을 눌러 촬영하세요.");
  }

  Future<void> _speak(String text) async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.5);
    await _tts.speak(text);
  }

  Future<void> _captureImage() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);

      if (photo == null) {
        await _speak("촬영이 취소되었습니다.");
        return;
      }

      setState(() {
        _isProcessing = true;
        _capturedImage = File(photo.path);
      });

      await Vibration.vibrate(duration: 200);
      await _speak("사진이 촬영되었습니다. 업로드 버튼을 눌러주세요.");

      setState(() {
        _isProcessing = false;
      });
    } catch (e) {
      await _speak("카메라 오류가 발생했습니다. 다시 시도해주세요.");
    }
  }

  void _uploadImage() {
    if (_capturedImage == null) {
      _speak("먼저 사진을 찍어주세요.");
      return;
    }

    _speak("처방전이 업로드되었습니다. 수고하셨습니다.");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ 처방전 업로드 완료')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('처방전 촬영'),
        backgroundColor: Colors.teal,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_capturedImage != null)
                Expanded(
                  child: Image.file(_capturedImage!, fit: BoxFit.contain),
                )
              else
                const Expanded(
                  child: Center(
                    child: Text(
                      '카메라로 처방전을 촬영하세요.',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ),
                ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isProcessing ? null : _captureImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  minimumSize: const Size(double.infinity, 80),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  '📷 촬영하기',
                  style: TextStyle(fontSize: 28, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _uploadImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize: const Size(double.infinity, 70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  '☁ 업로드하기',
                  style: TextStyle(fontSize: 22, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}