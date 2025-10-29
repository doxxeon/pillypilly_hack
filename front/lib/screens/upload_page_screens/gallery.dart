import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:pillypilly_h/api_services/api_helper.dart';
import 'package:pillypilly_h/services/theme_service.dart';

class PrescriptionUploadPage extends StatefulWidget {
  const PrescriptionUploadPage({Key? key}) : super(key: key);

  @override
  State<PrescriptionUploadPage> createState() => _PrescriptionUploadPageState();
}

class _PrescriptionUploadPageState extends State<PrescriptionUploadPage> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();
  File? _selectedImage;
  bool _isLoading = false;
  List<dynamic> _ocrResults = [];

  @override
  void initState() {
    super.initState();
    _announce("처방전 이미지를 선택하세요. 가운데 버튼을 누르면 갤러리를 열 수 있습니다.");
  }

  Future<void> _announce(String text) async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.47);
    await _tts.speak(text);
  }

  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) {
      await _announce("이미지가 선택되지 않았습니다. 다시 시도해주세요.");
      return;
    }
    setState(() {
      _selectedImage = File(file.path);
      _ocrResults.clear();
    });
    await _announce("이미지를 선택했습니다. 분석 버튼을 눌러주세요.");
  }

  Future<void> _analyzePrescription() async {
    if (_selectedImage == null) {
      await _announce("이미지를 먼저 선택해주세요.");
      return;
    }

    setState(() => _isLoading = true);
    await _announce("처방전을 분석 중입니다. 잠시만 기다려주세요.");
    await Vibration.vibrate(duration: 150);

    try {
      final dio = Dio();
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = '$baseUrl/api/v3/prescription-ocr-auto';
      final headers = await ApiHelper.getAuthHeaders();

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(_selectedImage!.path),
      });

      final res = await dio.post(url, data: formData, options: Options(headers: headers));

      if (res.statusCode == 200 && res.data['results'] != null) {
        setState(() => _ocrResults = res.data['results']);
        await _announce("총 ${_ocrResults.length}개의 약을 인식했습니다. 아래에서 각 약의 상세보기 버튼을 눌러주세요.");
        await Vibration.vibrate(duration: 300);
      } else {
        await _handleFailure();
      }
    } catch (e) {
      debugPrint("❌ OCR 오류: $e");
      await _handleFailure();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFailure() async {
    await _announce("분석에 실패했습니다. 다시 이미지를 선택해주세요.");
    await Vibration.vibrate(pattern: [0, 400, 150, 400]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("OCR 분석 실패. 다시 시도해주세요.",
            style: TextStyle(color: AppColors.textPrimary(context))),
        backgroundColor: AppColors.error(context),
      ),
    );
  }

  void _goToDetail(dynamic item) async {
    try {
      if (item == null) {
        await _announce("약 데이터가 유효하지 않습니다.");
        debugPrint("❌ item is null in _goToDetail");
        return;
      }

      final itemSeq = item["item_seq"];
      if (itemSeq == null || itemSeq.toString().isEmpty) {
        await _announce("이 약은 상세정보를 찾을 수 없습니다.");
        debugPrint("❌ Missing item_seq in item: $item");
        return;
      }

      final drugName = item["약품명"] ?? item["summary"]?["itemName"] ?? "알 수 없는 약";
      await _announce("$drugName의 상세 정보를 불러옵니다.");
      debugPrint("➡️ Navigating with itemSeq: $itemSeq");

      Navigator.pushNamed(
        context,
        '/drug_detail',
        arguments: {"itemSeq": itemSeq.toString()},
      );
    } catch (e) {
      debugPrint("❌ _goToDetail error: $e");
      await _announce("약 상세 정보를 불러오는 중 오류가 발생했습니다.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.primary(context),
        title: Text("처방전 분석", style: AppTextStyles.title(context).copyWith(color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              if (_selectedImage != null)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.accent(context), width: 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(_selectedImage!, height: 160, fit: BoxFit.cover),
                )
              else
                Icon(Icons.image_search, color: AppColors.accent(context).withOpacity(0.8), size: 90),

              const SizedBox(height: 24),

              if (!_isLoading)
                ElevatedButton(
                  onPressed: _pickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent(context),
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text("📂 갤러리에서 선택", style: AppTextStyles.largeButton(context)),
                ),

              const SizedBox(height: 12),

              if (!_isLoading)
                ElevatedButton(
                  onPressed: _analyzePrescription,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary(context),
                    minimumSize: const Size(double.infinity, 65),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text("🔍 OCR 분석하기", style: AppTextStyles.largeButton(context)),
                ),

              if (_isLoading) ...[
                const SizedBox(height: 24),
                CircularProgressIndicator(color: AppColors.accent(context)),
              ],

              const SizedBox(height: 16),

              if (_ocrResults.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    itemCount: _ocrResults.length,
                    itemBuilder: (context, i) {
                      final item = _ocrResults[i];
                      final valid = (item["보험코드"]?.toString().length ?? 0) >= 9;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: valid ? AppColors.card(context) : AppColors.errorLight(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: valid ? AppColors.accent(context) : AppColors.error(context),
                            width: 1.4,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "💊 ${item["약품명"] ?? "인식 실패"}",
                              style: AppTextStyles.body(context).copyWith(
                                color: valid ? AppColors.textPrimary(context) : AppColors.error(context),
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () => _goToDetail(item),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.confirm(context),
                                minimumSize: const Size(double.infinity, 55),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Text("🔎 상세보기", style: AppTextStyles.largeButton(context)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}