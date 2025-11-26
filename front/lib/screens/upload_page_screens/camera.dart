import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:pillypilly_h/api_services/api_helper.dart';
import '../../services/theme_service.dart';

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
  List<dynamic> _ocrResults = [];
  List<String> _validItemSeqs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak("처방전 촬영 페이지입니다. 중앙의 큰 버튼을 눌러 촬영하세요.");
    });
  }

  Future<void> _speak(String text) async {
    final theme = context.read<ThemeService>();
    if (!theme.isVoiceGuideEnabled) return;
    
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
        _ocrResults = [];
      });

      await Vibration.vibrate(duration: 200);
      await _speak("사진이 촬영되었습니다. 분석 중입니다.");

      await _uploadAndAnalyze();
    } catch (e) {
      await _speak("카메라 오류가 발생했습니다. 다시 시도해주세요.");
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _uploadAndAnalyze() async {
    if (_capturedImage == null) return;

    try {
      final dio = Dio();
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = '$baseUrl/api/v3/prescription-ocr-auto';
      final headers = await ApiHelper.getAuthHeaders();

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(_capturedImage!.path),
      });

      final res = await dio.post(url, data: formData, options: Options(headers: headers));

      if (res.statusCode == 200 && res.data['results'] != null) {
        setState(() => _ocrResults = res.data['results']);
        await _showOcrResults();
      } else {
        await _handleOcrFailure();
      }
    } catch (e) {
      debugPrint("❌ OCR 오류: $e");
      await _handleOcrFailure();
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _showOcrResults() async {
    if (_ocrResults.isEmpty) {
      await _handleOcrFailure();
      return;
    }

    await _speak("총 ${_ocrResults.length}개의 약을 인식했습니다.");

    // 약 이름 순차 음성 안내
    for (final item in _ocrResults) {
      final name = item["약품명"] ?? "이름을 인식하지 못했습니다.";
      await _speak(name);
      await Future.delayed(const Duration(milliseconds: 600));
    }

    // 9자리 미만 보험코드 검증 및 item_seq 필터링
    _validItemSeqs = _ocrResults
        .where((e) => (e["보험코드"]?.toString().length ?? 0) >= 9)
        .map<String>((e) => e["item_seq"].toString())
        .toList();

    if (_validItemSeqs.isEmpty) {
      await _handleOcrFailure();
      return;
    }

    await _speak("결과확인 버튼을 눌러 상세 정보를 확인할 수 있습니다.");
  }

  Future<void> _fetchIntegratedResult() async {
    try {
      final dio = Dio();
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = '$baseUrl/api/v3/log/by-edi-code';
      final headers = await ApiHelper.getAuthHeaders();

      final data = {"edi_codes": _validItemSeqs};

      final response = await dio.post(
        url,
        data: data,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200) {
        await _speak("통합 조회 결과를 불러왔습니다.");
        Navigator.pushNamed(
          context,
          '/drug_detail',
          arguments: {"drugData": response.data},
        );
      } else {
        await _speak("서버 조회 중 오류가 발생했습니다.");
      }
    } catch (e) {
      debugPrint("❌ 통합조회 오류: $e");
      await _speak("조회 중 오류가 발생했습니다.");
    }
  }

  Future<void> _handleOcrFailure() async {
    await _speak("처방전 인식에 실패했습니다. 다시 촬영해주세요.");
    await Vibration.vibrate(pattern: [0, 300, 100, 300]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('처방전 촬영'),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_capturedImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(_capturedImage!, fit: BoxFit.cover, height: 200),
              )
            else
              const SizedBox(
                height: 200,
                child: Center(child: Text('📷 처방전을 촬영해주세요.')),
              ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isProcessing ? null : _captureImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_isProcessing ? '분석 중...' : '📷 촬영하기',
                  style: const TextStyle(fontSize: 20, color: Colors.white)),
            ),

            const SizedBox(height: 20),

            if (_ocrResults.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _ocrResults.length,
                  itemBuilder: (context, i) {
                    final item = _ocrResults[i];
                    final summary = item["summary"] ?? {};
                    final valid = (item["보험코드"]?.toString().length ?? 0) >= 9;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: valid ? Colors.white : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          summary['imageUrl'] != null
                              ? Image.network(summary['imageUrl'], width: 60, height: 60, fit: BoxFit.cover)
                              : const Icon(Icons.medication, color: Colors.teal, size: 50),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(summary['itemName'] ?? item["약품명"] ?? '이름 없음',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(summary['entpName'] ?? '제조사 미상',
                                    style: const TextStyle(color: Colors.grey)),
                                if (!valid)
                                  const Text('⚠ 보험코드 오류', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            if (_ocrResults.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton.icon(
                  onPressed: _fetchIntegratedResult,
                  icon: const Icon(Icons.search),
                  label: const Text('결과 확인하기', style: TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}