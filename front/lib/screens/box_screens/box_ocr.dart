import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';

class BoxOcrScreen extends StatefulWidget {
  const BoxOcrScreen({super.key});

  @override
  State<BoxOcrScreen> createState() => _BoxOcrScreenState();
}

class _BoxOcrScreenState extends State<BoxOcrScreen> {
  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer();
  final FlutterTts tts = FlutterTts();

  File? _imageFile;
  String? _recognizedText;
  bool _isLoading = false;
  Map<String, dynamic>? _drugInfo;

  @override
  void dispose() {
    textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    await tts.speak(source == ImageSource.camera
        ? "카메라가 열립니다. 사진을 찍어주세요."
        : "갤러리가 열립니다. 이미지를 선택해주세요.");

    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _recognizedText = null;
      });
      await tts.speak("이미지가 선택되었습니다. 텍스트를 인식합니다.");
      Vibration.vibrate(duration: 150);
      await _performOCR();
    } else {
      await tts.speak("이미지가 선택되지 않았습니다.");
    }
  }

  Future<void> _performOCR() async {
    if (_imageFile == null) return;
    setState(() => _isLoading = true);
    await tts.speak("이미지에서 약 이름을 인식 중입니다. 잠시 기다려주세요.");

    final inputImage = InputImage.fromFile(_imageFile!);
    final RecognizedText recognizedText =
        await textRecognizer.processImage(inputImage);

    String text = recognizedText.text;
    setState(() {
      _recognizedText = text;
      _isLoading = false;
    });

    if (text.isEmpty) {
      await tts.speak("텍스트를 인식하지 못했습니다. 다시 시도해주세요.");
    } else {
      await tts.speak("텍스트 인식 완료. 약 정보를 불러옵니다.");
      Vibration.vibrate(duration: 200);
      await _fetchDrugInfo(text);
    }
  }

  Future<void> _fetchDrugInfo(String text) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://api.odcloud.kr/api/15054738/v1/uddi:example',
        queryParameters: {
          'drugName': text.split('\n').first,
          'serviceKey': 'YOUR_API_KEY_HERE',
        },
      );
      setState(() => _drugInfo = response.data);
      await tts.speak("약 정보 불러오기 완료. 아래 내용을 읽어주세요.");
      Vibration.vibrate(duration: 150);
    } catch (e) {
      await tts.speak("약 정보를 불러오지 못했습니다. 다시 시도해주세요.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = const ColorScheme.dark(
      background: Colors.black,
      primary: Color(0xFFFFEB3B),
      onPrimary: Colors.black,
    );

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: AppBar(
        title: const Text('약 상자 OCR 인식'),
        backgroundColor: scheme.background,
        foregroundColor: scheme.primary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                label: '약 상자 OCR 인식 화면',
                hint: '사진을 찍거나 이미지를 선택하여 텍스트를 인식합니다.',
                child: Container(
                  width: double.infinity,
                  height: 260,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                  child: _imageFile != null
                      ? Image.file(_imageFile!, fit: BoxFit.contain)
                      : const Center(
                          child: Text(
                            '이미지가 없습니다.\n아래 버튼을 눌러 업로드하세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                height: 1.4),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Column(
                  children: [
                    CircularProgressIndicator(color: Colors.yellow),
                    SizedBox(height: 12),
                    Text('텍스트 인식 중...', style: TextStyle(color: Colors.white)),
                  ],
                )
              else if (_recognizedText != null)
                _ResultView(recognizedText: _recognizedText!, drugInfo: _drugInfo)
              else
                const SizedBox(height: 0),

              const SizedBox(height: 20),
              Semantics(
                label: '이미지 업로드 버튼',
                hint: '카메라로 촬영하거나, 갤러리에서 이미지를 선택할 수 있습니다.',
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt, color: Colors.black),
                        label: const Text('촬영하기',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          minimumSize: const Size(double.infinity, 64),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.image, color: Colors.black),
                        label: const Text('이미지 선택',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          minimumSize: const Size(double.infinity, 64),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final String recognizedText;
  final Map<String, dynamic>? drugInfo;
  const _ResultView({required this.recognizedText, required this.drugInfo});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '인식 결과 영역',
      hint: '인식된 텍스트와 약 정보가 표시됩니다.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.yellow, width: 1.5),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🧾 인식된 텍스트',
                  style: TextStyle(
                      color: Colors.yellow,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(recognizedText,
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 18),
              if (drugInfo != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💊 약 정보',
                        style: TextStyle(
                            color: Colors.yellow,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('약 이름: ${drugInfo?["drugName"] ?? "정보 없음"}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                    Text('제조사: ${drugInfo?["manufacturer"] ?? "정보 없음"}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                    Text('효능: ${drugInfo?["effect"] ?? "정보 없음"}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}