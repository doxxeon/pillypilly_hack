// front/lib/screens/upload_page_screens/gallery.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:pillypilly_h/api_services/api_helper.dart';
import 'package:pillypilly_h/services/theme_service.dart';
import 'package:pillypilly_h/utils/app_colors.dart';
import 'package:pillypilly_h/utils/app_text_styles.dart';
import 'package:image/image.dart' as img;
import 'pill_capture.dart';

class PrescriptionUploadPage extends StatefulWidget {
  final File? initialImage;
  final bool autoAnalyze;
  
  const PrescriptionUploadPage({Key? key, this.initialImage, this.autoAnalyze = false}) : super(key: key);

  @override
  State<PrescriptionUploadPage> createState() => _PrescriptionUploadPageState();
}

enum _Stage { idle, picking, ready, analyzing }

class _PrescriptionUploadPageState extends State<PrescriptionUploadPage> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  CancelToken? _cancelToken;

  List<File> _selectedImages = [];
  int _currentIndex = 0;
  _Stage _stage = _Stage.idle;
  double _progress = 0.0;
  List<dynamic> _ocrResults = [];
  bool _busy = false;
  bool _hadError = false;
  String? _prescriptionId;
  int? _expectedCount;
  String? _sessionTtsText;

  // 캡션 대체용 스타일(AppTextStyles.caption 없는 프로젝트 호환)
  TextStyle _cap(BuildContext c) => AppTextStyles.body(c).copyWith(
        fontSize: 13,
        height: 1.3,
        color: AppColors.textPrimary(c).withOpacity(0.75),
      );

  @override
  void initState() {
    super.initState();
    // 촬영한 이미지가 있으면 자동으로 선택
    if (widget.initialImage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setInitialImage(widget.initialImage!);
      });
    } else {
      _announce(
        "처방전 업로드 화면입니다. "
        "갤러리에서 이미지를 선택하고, 분석하기 버튼을 눌러주세요.",
      );
    }
  }

  Future<void> _setInitialImage(File image) async {
    setState(() {
      _selectedImages = [image];
      _currentIndex = 0;
      _stage = _Stage.ready;
    });
    await _vibrate(duration: 100);
    
    // 자동 분석이 활성화되어 있으면 바로 분석 시작
    if (widget.autoAnalyze) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _analyzePrescription();
    } else {
      await _announce("이미지가 선택되었습니다. 분석하기 버튼을 눌러주세요.");
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel("dispose");
    _tts.stop();
    super.dispose();
  }

  // ===== 공용 유틸 =====

  Future<void> _announce(String text, {bool interrupt = true}) async {
    try {
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.47);
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _vibrate({int duration = 120}) async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.vibrate(duration: duration);
      }
    } catch (_) {}
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color ?? Colors.black87,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _cleanBase(String raw) {
    if (raw.isEmpty) return raw;
    final t = raw.trim();
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  void _reset({bool keepImages = false}) {
    setState(() {
      if (!keepImages) {
        _selectedImages = [];
        _currentIndex = 0;
      }
      _stage = keepImages ? _Stage.ready : _Stage.idle;
      _progress = 0.0;
      _ocrResults = [];
      _busy = false;
      _hadError = false;
      _prescriptionId = null;
      _expectedCount = null;
      _sessionTtsText = null;
    });
  }

  // ===== 이미지 선택/전처리 =====

  Future<File> _prepImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return file;

      // EXIF 방향 보정
      img.Image fixed = img.bakeOrientation(decoded);

      // 항상 세로(포트레이트) 기준 3024 x 4032로 맞추기
      const targetWidth = 3024;
      const targetHeight = 4032;

      // 가로로 누운 경우를 대비해, 세로가 더 길게 되도록 회전
      if (fixed.width > fixed.height) {
        fixed = img.copyRotate(fixed, angle: 90);
      }

      final resized = img.copyResize(
        fixed,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.cubic,
      );

      final jpg = img.encodeJpg(resized, quality: 92);
      final out = File('${file.path}_opt.jpg');
      await out.writeAsBytes(jpg, flush: true);
      return out;
    } catch (_) {
      // 전처리 중 문제가 생기면 원본 파일로 fallback
      return file;
    }
  }

  Future<void> _pickImages() async {
    if (_busy) return;
    setState(() {
      _stage = _Stage.picking;
      _hadError = false;
      _progress = 0.0;
      _busy = true;
    });

    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 95,
        requestFullMetadata: false,
      );

      if (!mounted) return;

      if (files.isEmpty) {
        _reset(keepImages: false);
        await _announce("이미지가 선택되지 않았습니다. 다시 시도해주세요.");
        return;
      }

      setState(() {
        _selectedImages = files.map((x) => File(x.path)).toList();
        _currentIndex = 0;
        _ocrResults.clear();
        _stage = _Stage.ready;
      });

      await _announce(
        "${_selectedImages.length}장의 이미지를 선택했습니다. "
        "분석하기 버튼을 누르면 시작합니다.",
      );
      await _vibrate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ===== 업로드/분석 =====

  Future<Response> _postOnce({
    required File fileToSend,
    required String url,
    required String fieldName,
    required int index,
    required int total,
  }) async {
    _cancelToken?.cancel("restart");
    _cancelToken = CancelToken();

    final filename = fileToSend.path.split('/').last;

    final formData = FormData.fromMap({
      fieldName: MultipartFile.fromFileSync(fileToSend.path, filename: filename),
      'pageIndex': index,
      // 서버 요구 시 추가:
      // 'source': 'android',
      // 'lang': 'ko',
    });

    return _dio.post(
      url,
      data: formData,
      cancelToken: _cancelToken,
      options: Options(
        headers: await ApiHelper.getAuthHeaders(),
        sendTimeout: const Duration(seconds: 20),
      ),
      onSendProgress: (sent, totalBytes) {
        if (!mounted || totalBytes <= 0) return;
        final unit = 1.0 / total;
        final uploadP = (sent / totalBytes).clamp(0.0, 1.0);
        final globalP = (index * unit) + (unit * 0.7 * uploadP);
        setState(() => _progress = globalP);
      },
    );
  }

  Future<List<dynamic>> _uploadAndAnalyzeSingle({
    required File fileToSend,
    required String baseUrl,
    required int index,
    required int total,
  }) async {
    final unit = 1.0 / total;
    final url = '${_cleanBase(baseUrl)}/api/v3/prescription-ocr-auto';

    Response res;

    try {
      // 1차: field = file
      res = await _postOnce(
        fileToSend: fileToSend,
        url: url,
        fieldName: 'file',
        index: index,
        total: total,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        // 2차: field = image 재시도
        res = await _postOnce(
          fileToSend: fileToSend,
          url: url,
          fieldName: 'image',
          index: index,
          total: total,
        );
      } else {
        rethrow;
      }
    }

    if (!mounted) return const [];

    setState(() {
      // 업로드 이후 서버 처리 구간 가중(0.85)
      _progress = (index * unit) + (unit * 0.85);
    });

    if (res.statusCode == 200 && res.data is Map) {
      final data = res.data as Map;

      // 세션 정보(prescription_id, expected_count, tts_text 등) 갱신
      final sid = data['prescription_id'] ?? data['id'];
      if (sid != null && sid.toString().trim().isNotEmpty) {
        _prescriptionId = sid.toString().trim();
      }

      final expected = data['expected_count'] ?? data['expectedCount'];
      if (expected is int) {
        _expectedCount = expected;
      } else if (expected is String) {
        final parsed = int.tryParse(expected);
        if (parsed != null) _expectedCount = parsed;
      }

      final tts = data['tts_text'] ?? data['ttsText'];
      if (tts is String && tts.trim().isNotEmpty) {
        _sessionTtsText = tts.trim();
      }

      // 약 목록(results 등) 추출
      List<dynamic> results = const [];
      if (data['results'] is List) {
        results = (data['results'] as List).cast<dynamic>();
      } else if (data['items'] is List) {
        results = (data['items'] as List).cast<dynamic>();
      }

      setState(() => _progress = ((index + 1) * unit).clamp(0.0, 1.0));

      // 결과 리스트가 없더라도 빈 리스트를 반환하여 상위 로직이 안전하게 동작하도록 처리
      return results;
    }

    final msg = () {
      final d = res.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
      if (d is Map && d['error'] != null) return d['error'].toString();
      return d?.toString();
    }();

    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: 'Unexpected response (${res.statusCode}). Message: $msg',
      type: DioExceptionType.badResponse,
    );
  }

  Future<void> _analyzePrescription() async {
    if (_busy) return;
    if (_selectedImages.isEmpty) {
      await _announce("먼저 이미지를 선택해주세요.");
      _showSnack("이미지를 먼저 선택하세요.", color: Colors.redAccent);
      return;
    }

    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    if (baseUrl.isEmpty) {
      _showSnack(".env의 API_BASE_URL이 설정되지 않았습니다.", color: Colors.redAccent);
      await _announce("서버 주소가 설정되지 않았습니다.");
      return;
    }

    setState(() {
      _stage = _Stage.analyzing;
      _progress = 0.02;
      _ocrResults.clear();
      _busy = true;
      _hadError = false;
    });

    await _announce(
      "처방전을 분석합니다. 진행률은 화면 상단에 표시되고, "
      "음성으로도 안내됩니다.",
    );
    await _vibrate();

    try {
      final total = _selectedImages.length;

      for (int i = 0; i < total; i++) {
        if (!mounted) return;
        final prepped = await _prepImage(_selectedImages[i]);
        final pageResults = await _uploadAndAnalyzeSingle(
          fileToSend: prepped,
          baseUrl: baseUrl,
          index: i,
          total: total,
        );
        setState(() => _ocrResults.addAll(pageResults));

        final pct = ((_progress * 100).clamp(0, 100)).toStringAsFixed(0);
        // 너무 자주 말하지 않도록 조절
        if (i == 0 || i == total - 1 || i % 2 == 1) {
          _announce("분석 진행률 ${pct}퍼센트", interrupt: false);
        }
      }

      if (!mounted) return;

      setState(() {
        _progress = 1.0;
        _stage = _Stage.ready;
        _busy = false;
      });

      // 세션에서 내려온 TTS 문구가 있으면 우선 사용, 없으면 기본 안내문 사용
      if (_sessionTtsText != null && _sessionTtsText!.trim().isNotEmpty) {
        await _announce(_sessionTtsText!);
      } else {
        await _announce(
          "처방 분석이 완료되었습니다. 처방 약 목록 ${_ocrResults.length}개 감지됨.",
        );
      }
      await _vibrate(duration: 220);
      _showSnack("분석 완료: ${_ocrResults.length}개 인식");

      // 전체 화면 결과 팝업 표시
      await _showResultsSheet();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;

      String pretty = "서버 오류";
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        pretty = "네트워크 시간 초과. 다시 시도해주세요.";
      } else if (e.type == DioExceptionType.connectionError) {
        pretty = "서버에 연결할 수 없습니다. 네트워크를 확인해주세요.";
      } else if (e.type == DioExceptionType.cancel) {
        pretty = "분석이 취소되었습니다.";
      } else if (code == 400) {
        pretty = "요청 형식이 올바르지 않습니다.";
      } else if (code == 422) {
        final hint = (body is Map && body['message'] != null)
            ? body['message'].toString()
            : body?.toString();
        pretty = "요청 검증 실패: ${hint ?? '이미지 형식을 확인해주세요'}";
      } else if (code == 500) {
        pretty = "서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해주세요.";
      } else if (code == 502) {
        final errorMsg = body is Map 
            ? (body['error']?['message'] ?? body['message'] ?? '외부 서비스 연결 실패')
            : '서버가 외부 서비스에 연결할 수 없습니다';
        pretty = "서버 연결 오류: $errorMsg";
      } else if (code == 503) {
        pretty = "서버가 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해주세요.";
      } else if (code != null) {
        pretty = "서버 오류 ($code). 다시 시도해주세요.";
      }

      setState(() {
        _hadError = true;
      });

      _showSnack(pretty, color: Colors.redAccent);
      await _announce("분석에 실패했습니다. $pretty");
    } catch (e) {
      setState(() {
        _hadError = true;
      });
      
      String errorMsg = "분석에 실패했습니다.";
      final errorStr = e.toString();
      if (errorStr.contains('Client') || errorStr.contains('FileSystem')) {
        errorMsg = "이미지 파일을 읽을 수 없습니다. 파일을 확인해주세요.";
      } else if (errorStr.contains('Socket') || errorStr.contains('Network')) {
        errorMsg = "네트워크 연결 오류가 발생했습니다. 인터넷 연결을 확인해주세요.";
      } else {
        errorMsg = "알 수 없는 오류가 발생했습니다: ${errorStr.length > 50 ? errorStr.substring(0, 50) : errorStr}";
      }
      
      _showSnack(errorMsg, color: Colors.redAccent);
      await _announce(errorMsg);
    } finally {
      if (!mounted) return;
      // 항상 버튼 복구 + 상태 복원
      setState(() {
        _busy = false;
        if (_stage == _Stage.analyzing) {
          _stage = _Stage.ready;
        }
      });
    }
  }

  void _cancelAnalyze() {
    _cancelToken?.cancel("user_cancel");
    _announce("분석을 취소했습니다.");
    _showSnack("분석 취소됨");
    setState(() {
      _busy = false;
      _stage = _Stage.ready;
      _progress = 0.0;
    });
  }

  void _prevImage() {
    if (_selectedImages.isEmpty) return;
    setState(
      () => _currentIndex = (_currentIndex - 1).clamp(0, _selectedImages.length - 1),
    );
  }

  void _nextImage() {
    if (_selectedImages.isEmpty) return;
    setState(
      () => _currentIndex = (_currentIndex + 1).clamp(0, _selectedImages.length - 1),
    );
  }

  Future<void> _goToDetail(dynamic item) async {
    try {
      // 백엔드 응답: itemSeq, itemName 기반
      final itemSeq = item["itemSeq"] ??
          item["item_seq"] ??
          item["summary"]?["itemSeq"];

      if (itemSeq == null || itemSeq.toString().trim().isEmpty) return;

      Navigator.pushNamed(
        context,
        '/drug_detail',
        arguments: {"itemSeq": itemSeq.toString()},
      );
    } catch (_) {}
  }

  Future<void> _showResultsSheet() async {
    if (!mounted) return;
    if (_ocrResults.isEmpty) return;

    await _announce(
      "분석 결과 화면입니다. "
      "총 ${_ocrResults.length}개의 약을 인식했습니다. "
      "아래에서 약을 선택하거나, 화면 하단의 버튼으로 다음 단계를 진행할 수 있습니다.",
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.black54,
      builder: (ctx) {
        final bg = AppColors.background(ctx);
        final accent = AppColors.accent(ctx);
        final primary = AppColors.primary(ctx);

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.9,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Semantics(
            container: true,
            label: "처방 분석 결과 팝업",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "분석 결과",
                        style: AppTextStyles.title(ctx),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "총 ${_ocrResults.length}개의 약을 인식했습니다. "
                        "목록에서 약을 선택하면 상세 정보를 볼 수 있고, "
                        "하단의 버튼으로 촬영 단계로 진행하거나 종료할 수 있습니다.",
                        style: _cap(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // 팝업 내부 결과 리스트
                Expanded(
                  child: ListView.builder(
                    itemCount: _ocrResults.length,
                    itemBuilder: (context, i) {
                      final item = _ocrResults[i];
                      final name = (item["약품명"] ??
                              item["itemName"] ??
                              item["item_name"] ??
                              "인식 실패")
                          .toString();
                      return Semantics(
                        button: true,
                        label: "의약품 $name",
                        hint: "탭 하면 상세 정보 화면으로 이동합니다",
                        child: Card(
                          elevation: 0.5,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 18,
                            ),
                            onTap: () {
                              // 팝업은 유지한 채로 상세 화면을 위에 쌓습니다.
                              _goToDetail(item);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // 하단 액션 버튼들
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: "끝내기",
                          hint: "분석을 종료하고 홈 화면으로 돌아갑니다",
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop(); // 팝업 닫기
                              _onFinishSession();
                            },
                            icon: const Icon(Icons.home),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            label: const Text("끝내기"),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: "알약 찍기",
                          hint:
                              "인식할 알약 개수를 선택하고 알약 촬영 단계로 이동합니다",
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop(); // 팝업 닫기
                              _onGoToPillCaptureSetup();
                            },
                            icon: const Icon(Icons.camera_alt),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                            ),
                            label: const Text("알약 찍기"),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    // 팝업이 닫힌 이후 다시 분석하면 새로 열릴 수 있도록 플래그 초기화
  }

  // ==== 분석 이후 Flow: 끝내기 / 알약 찍기 ====

  void _onFinishSession() {
    _announce("분석을 마치고 홈 화면으로 돌아갑니다.");
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _showPillCountSheet(int defaultCount) {
    if (!mounted) return;

    final maxCount = _ocrResults.length > 0 ? _ocrResults.length : defaultCount;
    int currentCount = defaultCount.clamp(1, maxCount);

    _announce(
      "알약 촬영 단계로 이동하기 전에, 촬영할 알약 개수를 선택하는 화면입니다. "
      "기본 개수는 ${currentCount}개 입니다.",
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      useSafeArea: true,
      builder: (ctx) {
        final bg = AppColors.background(ctx);
        final primary = AppColors.primary(ctx);

        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return Semantics(
                container: true,
                label: "알약 개수 선택 화면",
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    Text(
                      "검색할 알약 개수",
                      style: AppTextStyles.title(ctx),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "이번에 인식할 알약 사진 개수를 선택해주세요. "
                      "기본값은 처방전에서 인식된 약 개수입니다.",
                      style: _cap(ctx),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Semantics(
                          button: true,
                          label: "알약 개수 줄이기",
                          child: IconButton(
                            onPressed: () {
                              if (currentCount > 1) {
                                setModalState(() {
                                  currentCount -= 1;
                                });
                              }
                            },
                            icon: const Icon(Icons.remove_circle_outline, size: 30),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          "$currentCount 개",
                          style: AppTextStyles.title(ctx).copyWith(fontSize: 22),
                        ),
                        const SizedBox(width: 16),
                        Semantics(
                          button: true,
                          label: "알약 개수 늘리기",
                          child: IconButton(
                            onPressed: () {
                              if (currentCount < maxCount) {
                                setModalState(() {
                                  currentCount += 1;
                                });
                              }
                            },
                            icon: const Icon(Icons.add_circle_outline, size: 30),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: primary),
                              foregroundColor: bg == Colors.white ? Colors.black : Colors.white,
                            ),
                            child: Text(
                              "취소",
                              style: TextStyle(
                                color: bg == Colors.white ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _announce(
                                "총 ${currentCount}개의 알약을 촬영하는 단계로 이동합니다.",
                              );
                              if (_prescriptionId == null ||
                                  _prescriptionId!.trim().isEmpty) {
                                _showSnack(
                                  "처방전 세션 정보가 없습니다. 다시 시도해주세요.",
                                  color: Colors.redAccent,
                                );
                                return;
                              }

                              // 실제 알약 촬영 화면(PillCapturePage)으로 이동
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PillCapturePage(
                                    prescriptionId: _prescriptionId!.trim(),
                                    totalCount: currentCount,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("알약 촬영 시작"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _onGoToPillCaptureSetup() {
    // 1) 세션 ID 확인
    if (_prescriptionId == null || _prescriptionId!.trim().isEmpty) {
      _showSnack("처방전 세션 정보가 없습니다. 다시 시도해주세요.", color: Colors.redAccent);
      _announce("처방전 세션 정보가 없어 알약 촬영 단계로 이동할 수 없습니다.");
      return;
    }

    // 2) expected_count가 0이거나 null인 경우, 인식된 약 개수(_ocrResults.length)를 사용
    int defaultCount;
    if (_expectedCount != null && _expectedCount! > 0) {
      defaultCount = _expectedCount!;
    } else {
      defaultCount = _ocrResults.length;
    }

    if (defaultCount <= 0) {
      _showSnack("인식된 약 정보가 없습니다. 알약 촬영을 진행할 수 없습니다.",
          color: Colors.redAccent);
      _announce("인식된 약 정보가 없어 알약 촬영을 진행할 수 없습니다.");
      return;
    }

    // 개수 선택 바텀시트로 먼저 진입
    _showPillCountSheet(defaultCount);
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.background(context);
    final accent = AppColors.accent(context);
    final primary = AppColors.primary(context);

    final hasImages = _selectedImages.isNotEmpty;
    final previewFile = hasImages ? _selectedImages[_currentIndex] : null;

    final canAnalyze = hasImages && !_busy;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: primary,
        title: const Text(
          "처방전 업로드/분석",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Semantics(
              container: true,
              label: "처방전 업로드 본문",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 프리뷰
                  Semantics(
                    label: hasImages
                        ? "선택된 이미지 미리보기 ${_currentIndex + 1} / ${_selectedImages.length}"
                        : "이미지가 선택되지 않았습니다",
                    child: Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: AppColors.card(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: accent, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: previewFile != null
                          ? Image.file(previewFile, fit: BoxFit.cover)
                          : Center(
                              child: Text(
                                "이미지를 선택하세요",
                                style: _cap(context),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 이미지 이동 버튼
                  if (hasImages)
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: "이전 이미지",
                            hint: "왼쪽으로 이동",
                            child: ElevatedButton.icon(
                              onPressed: _busy ? null : _prevImage,
                              icon: const Icon(Icons.arrow_back),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor: AppColors.card(context),
                                foregroundColor: AppColors.textPrimary(context),
                              ),
                              label: const Text("이전"),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: "다음 이미지",
                            hint: "오른쪽으로 이동",
                            child: ElevatedButton.icon(
                              onPressed: _busy ? null : _nextImage,
                              icon: const Icon(Icons.arrow_forward),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor: AppColors.card(context),
                                foregroundColor: AppColors.textPrimary(context),
                              ),
                              label: const Text("다음"),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (hasImages) const SizedBox(height: 8),
                  if (hasImages)
                    Center(
                      child: Text(
                        "현재 ${_currentIndex + 1} / ${_selectedImages.length}",
                        style: _cap(context),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // 진행 바(상단)
                  if (_stage == _Stage.analyzing)
                    Semantics(
                      liveRegion: true,
                      label: "분석 진행률",
                      value: "${(_progress * 100).clamp(0, 100).toStringAsFixed(0)} 퍼센트",
                      child: LinearProgressIndicator(
                        value: _progress,
                        color: accent,
                      ),
                    ),

                  const SizedBox(height: 10),

                  // 주요 액션 버튼
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: "갤러리에서 이미지 선택",
                          hint: "처방전 사진을 고릅니다",
                          child: ElevatedButton.icon(
                            onPressed: _busy ? null : _pickImages,
                            icon: const Icon(Icons.photo_library),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                            ),
                            label: const Text("갤러리에서 선택"),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: "분석하기",
                          hint: canAnalyze
                              ? "선택한 이미지를 서버로 보내 분석합니다"
                              : "이미지를 먼저 선택해야 합니다",
                          child: ElevatedButton.icon(
                            onPressed: canAnalyze ? _analyzePrescription : null,
                            icon: const Icon(Icons.search),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: primary.withOpacity(0.4),
                            ),
                            label: const Text("분석하기"),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 취소/재시도
                  if (_stage == _Stage.analyzing) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      button: true,
                      label: "분석 취소",
                      hint: "현재 진행 중인 분석을 중단합니다",
                      child: OutlinedButton.icon(
                        onPressed: _cancelAnalyze,
                        icon: const Icon(Icons.cancel),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        label: const Text("취소"),
                      ),
                    ),
                  ] else if (_hadError) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      button: true,
                      label: "재시도",
                      hint: "분석을 다시 시도합니다",
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _analyzePrescription,
                        icon: const Icon(Icons.refresh),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        label: const Text("재시도"),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  const SizedBox(height: 12),

                  // 분석 완료 안내 (결과는 별도 팝업에서만 확인)
                  if (_ocrResults.isNotEmpty)
                    Semantics(
                      button: true,
                      label: "분석 결과 다시 보기",
                      hint: "탭 하면 분석 결과 팝업 화면을 다시 엽니다",
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _showResultsSheet,
                        icon: const Icon(Icons.list_alt),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text("분석 결과 다시 보기"),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 분석 중 오버레이(큰 글자 + 백드롭)
          if (_stage == _Stage.analyzing)
            Semantics(
              liveRegion: true,
              label: "분석 중 오버레이",
              child: Container(
                color: Colors.black.withOpacity(0.45),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: AppColors.card(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.medical_information, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        "처방전 분석 중",
                        style: AppTextStyles.title(context),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _progress,
                        color: accent,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%",
                        style: AppTextStyles.body(context).copyWith(
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _cancelAnalyze,
                              icon: const Icon(Icons.cancel),
                              label: const Text("취소"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
