import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/loading_widget.dart';

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
  bool _isProcessing = false;
  String? _errorMessage;
  Map<String, dynamic>? _drugInfo;

  @override
  void dispose() {
    textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source, ThemeService theme) async {
    if (theme.isVoiceGuideEnabled) {
      await tts.speak(source == ImageSource.camera
          ? "카메라가 열립니다. 사진을 찍어주세요."
          : "갤러리가 열립니다. 이미지를 선택해주세요.");
    }

    final pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
        _recognizedText = null;
        _errorMessage = null;
      });
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("이미지가 선택되었습니다. 텍스트를 인식합니다.");
      }
      Vibration.vibrate(duration: 150);
      await _performOCR(theme);
    } else {
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("이미지가 선택되지 않았습니다.");
      }
    }
  }

  Future<void> _performOCR(ThemeService theme) async {
    if (_imageFile == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    if (theme.isVoiceGuideEnabled) {
      await tts.speak("이미지에서 약 이름을 인식 중입니다. 잠시 기다려주세요.");
    }

    try {
      final inputImage = InputImage.fromFile(_imageFile!);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);

      String text = recognizedText.text;
      setState(() {
        _recognizedText = text;
        _isLoading = false;
      });

      if (text.isEmpty) {
        setState(() {
          _errorMessage = "텍스트를 인식하지 못했습니다. 다시 시도해주세요.";
        });
        if (theme.isVoiceGuideEnabled) {
          await tts.speak("텍스트를 인식하지 못했습니다. 다시 시도해주세요.");
        }
      } else {
        if (theme.isVoiceGuideEnabled) {
          await tts.speak("텍스트 인식 완료. 약 정보를 불러옵니다.");
        }
        Vibration.vibrate(duration: 200);
        await _fetchDrugInfo(text, theme);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "텍스트 인식 중 오류가 발생했습니다.";
        _isLoading = false;
      });
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("텍스트 인식 중 오류가 발생했습니다.");
      }
    }
  }

  Future<void> _fetchDrugInfo(String text, ThemeService theme) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("약 정보를 검색 중입니다. 잠시만 기다려주세요.");
      }

      final dio = Dio();
      final response = await dio.get(
        'https://api.odcloud.kr/api/15054738/v1/uddi:example',
        queryParameters: {
          'drugName': text.split('\n').first,
          'serviceKey': 'YOUR_API_KEY_HERE',
        },
      );
      
      setState(() {
        _drugInfo = response.data;
        _isProcessing = false;
      });
      
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("약 정보 불러오기 완료. 아래 내용을 읽어주세요.");
      }
      Vibration.vibrate(duration: 150);
    } catch (e) {
      setState(() {
        _errorMessage = "약 정보를 불러오지 못했습니다. 다시 시도해주세요.";
        _isProcessing = false;
      });
      if (theme.isVoiceGuideEnabled) {
        await tts.speak("약 정보를 불러오지 못했습니다. 다시 시도해주세요.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '약 상자 OCR 인식',
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
                        color: theme.backgroundColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.primaryColor, width: 2),
                      ),
                      child: _imageFile != null
                          ? Image.file(_imageFile!, fit: BoxFit.contain)
                          : Center(
                              child: Text(
                                '이미지가 없습니다.\n아래 버튼을 눌러 업로드하세요.',
                                textAlign: TextAlign.center,
                                style: theme.bodyTextStyle.copyWith(
                                  fontSize: 16 * theme.fontScale,
                                  color: theme.textColor.withOpacity(0.7),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_isLoading || _isProcessing)
                    const LoadingWidget(
                      message: "텍스트를 인식하고 있습니다...",
                    )
                  else if (_errorMessage != null)
                    CustomErrorWidget(
                      message: _errorMessage!,
                      onRetry: () {
                        setState(() {
                          _errorMessage = null;
                          _imageFile = null;
                          _recognizedText = null;
                          _drugInfo = null;
                        });
                      },
                    )
                  else if (_recognizedText != null)
                    _buildResultCard(theme)
                  else
                    _buildActionButtons(theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(ThemeService theme) {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.camera_alt, size: 28),
          label: Text(
            '카메라로 촬영',
            style: theme.buttonTextStyle,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.buttonColor,
            foregroundColor: theme.buttonTextColor,
            minimumSize: const Size(200, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _pickImage(ImageSource.camera, theme),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.photo_library, size: 28),
          label: Text(
            '갤러리에서 선택',
            style: theme.buttonTextStyle,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.buttonColor,
            foregroundColor: theme.buttonTextColor,
            minimumSize: const Size(200, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => _pickImage(ImageSource.gallery, theme),
        ),
      ],
    );
  }

  Widget _buildResultCard(ThemeService theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.buttonColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '인식된 텍스트:',
            style: theme.buttonTextStyle.copyWith(
              fontSize: 18 * theme.fontScale,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _recognizedText ?? '',
            style: theme.bodyTextStyle.copyWith(
              fontSize: 16 * theme.fontScale,
              color: theme.buttonTextColor,
            ),
          ),
          if (_drugInfo != null) ...[
            const SizedBox(height: 20),
            Text(
              '약 정보:',
              style: theme.buttonTextStyle.copyWith(
                fontSize: 18 * theme.fontScale,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _drugInfo.toString(),
              style: theme.bodyTextStyle.copyWith(
                fontSize: 14 * theme.fontScale,
                color: theme.buttonTextColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}