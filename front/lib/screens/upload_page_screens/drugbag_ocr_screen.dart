import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

import '../../services/theme_service.dart';
import '../../services/prescription_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import '../../widgets/loading_widget.dart';
import 'pill_capture.dart';
import 'drugbag_camera_screen.dart';
import '../details/drug_detail.dart';

class DrugbagOcrScreen extends StatefulWidget {
  final ImageSource? initialSource;
  
  const DrugbagOcrScreen({
    Key? key,
    this.initialSource,
  }) : super(key: key);

  @override
  State<DrugbagOcrScreen> createState() => _DrugbagOcrScreenState();
}

class _DrugbagOcrScreenState extends State<DrugbagOcrScreen> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();
  final PrescriptionService _prescriptionService = PrescriptionService();
  
  File? _selectedImage;
  bool _isProcessing = false;
  String? _errorMessage;
  Map<String, dynamic>? _ocrResult;
  int? _expectedCount;
  bool _isSaved = false; // 저장 여부 추적

  @override
  void initState() {
    super.initState();
    _initVoiceGuide();
    // 팝업에서 선택한 소스가 있으면 바로 이미지 선택
    if (widget.initialSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickImage(widget.initialSource!);
      });
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _initVoiceGuide() async {
    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.5);
      await _tts.speak(
        "약봉투 인식 화면입니다. "
        "약봉투 이미지를 촬영하거나 갤러리에서 선택하세요. "
        "선택적으로 알약 개수를 미리 입력할 수 있습니다.",
      );
    }
  }

  Future<void> _announce(String text) async {
    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.5);
      await _tts.stop();
      await _tts.speak(text);
    }
    // Talkback을 위한 Semantics 업데이트
    SemanticsService.announce(text, TextDirection.ltr);
  }

  Future<void> _vibrate({int duration = 120}) async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        await Vibration.vibrate(duration: duration);
      }
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      File imageFile;
      
      if (source == ImageSource.camera) {
        // 가로형 카메라 화면으로 이동
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DrugbagCameraScreen(),
          ),
        );
        
        if (result is! File) {
          await _announce("촬영이 취소되었습니다.");
          return;
        }
        
        imageFile = result;
      } else {
        // 갤러리에서 선택
        final XFile? picked = await _picker.pickImage(
          source: source,
          imageQuality: 95,
        );

        if (picked == null) {
          await _announce("이미지 선택이 취소되었습니다.");
          return;
        }
        
        imageFile = File(picked.path);
      }

      setState(() {
        _selectedImage = imageFile;
        _errorMessage = null;
        _ocrResult = null;
      });

      await _vibrate(duration: 100);
      await _announce("이미지가 선택되었습니다. 분석하기 버튼을 눌러주세요.");
    } catch (e) {
      setState(() {
        _errorMessage = "이미지 선택 중 오류가 발생했습니다.";
      });
      await _announce(_errorMessage!);
    }
  }

  /// 이미지를 90도 회전시킨 새 파일 생성 (EXIF 정보 제거)
  Future<File?> _rotateImage(File imageFile, int degrees) async {
    try {
      debugPrint('🔄 [약봉투 회전] 이미지 회전 시작: ${degrees}도');
      final bytes = await imageFile.readAsBytes();
      debugPrint('🔄 [약봉투 회전] 원본 이미지 크기: ${bytes.length} bytes');
      
      // EXIF 방향 정보를 이미지에 적용하고 제거 (bakeOrientation)
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        debugPrint('❌ [약봉투 회전] 이미지 디코딩 실패');
        return null;
      }
      
      // EXIF 방향 정보 적용 (이미 회전된 경우를 고려)
      final normalizedImage = img.bakeOrientation(decodedImage);
      debugPrint('🔄 [약봉투 회전] EXIF 정규화 후 이미지 크기: ${normalizedImage.width}x${normalizedImage.height}');
      
      // 추가 회전 적용
      final rotatedImage = img.copyRotate(normalizedImage, angle: degrees);
      debugPrint('🔄 [약봉투 회전] 회전된 이미지 크기: ${rotatedImage.width}x${rotatedImage.height}');
      
      // EXIF 없이 새로 인코딩 (quality 95로 고화질 유지)
      final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotatedImage, quality: 95));
      debugPrint('🔄 [약봉투 회전] 회전된 이미지 바이트 크기: ${rotatedBytes.length} bytes');
      
      // 임시 파일 생성
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/drugbag_rotated_${DateTime.now().millisecondsSinceEpoch}_$degrees.jpg');
      await tempFile.writeAsBytes(rotatedBytes);
      
      debugPrint('✅ [약봉투 회전] 회전된 이미지 저장 완료: ${tempFile.path}');
      return tempFile;
    } catch (e, stackTrace) {
      debugPrint('❌ [약봉투 회전] 이미지 회전 오류: $e');
      debugPrint('❌ [약봉투 회전] 스택 트레이스: $stackTrace');
      return null;
    }
  }

  /// 회전 재시도가 필요한 에러인지 확인 (헤더 에러, crop 영역 에러 등)
  bool _shouldRetryWithRotation(dynamic responseData) {
    if (responseData == null) {
      debugPrint('🔍 [약봉투 에러 감지] responseData가 null입니다');
      return false;
    }
    
    debugPrint('🔍 [약봉투 에러 감지] responseData 타입: ${responseData.runtimeType}');
    debugPrint('🔍 [약봉투 에러 감지] responseData 전체 내용: $responseData');
    
    // 모든 가능한 필드를 확인
    String errorMessage = '';
    if (responseData is Map) {
      // 모든 가능한 필드에서 에러 메시지 추출
      errorMessage = (responseData['message'] ?? 
                     responseData['error']?['message'] ?? 
                     responseData['error']?['detail'] ??
                     responseData['detail'] ??
                     responseData['msg'] ??
                     responseData['error_message'] ??
                     responseData['errorMessage'] ??
                     '').toString();
      
      // 중첩된 error 객체도 확인
      if (errorMessage.isEmpty && responseData['error'] is Map) {
        final errorMap = responseData['error'] as Map;
        errorMessage = (errorMap['message'] ?? 
                       errorMap['detail'] ??
                       errorMap['msg'] ??
                       '').toString();
      }
      
      // responseData 전체를 문자열로 변환해서도 확인
      if (errorMessage.isEmpty) {
        errorMessage = responseData.toString();
      }
    } else {
      errorMessage = responseData.toString();
    }
    
    final errorMessageLower = errorMessage.toLowerCase();
    debugPrint('🔍 [약봉투 에러 감지] 추출된 에러 메시지: $errorMessage');
    debugPrint('🔍 [약봉투 에러 감지] 소문자 변환: $errorMessageLower');
    
    // 백엔드에서 이미 모든 회전 시도를 했다는 신호가 있으면 프론트엔드에서 재시도하지 않음
    if (errorMessageLower.contains('모든 회전 시도 실패') || 
        errorMessageLower.contains('all rotation attempts failed')) {
      debugPrint('🔍 [약봉투 에러 감지] 백엔드에서 이미 모든 회전 시도 완료 - 프론트엔드 재시도 안 함');
      return false;
    }
    
    // 회전 재시도가 필요한 에러들:
    // 1. 약품명 헤더를 찾지 못한 에러
    final hasHeaderKeyword = errorMessageLower.contains('약품명') || 
                            errorMessageLower.contains('헤더') ||
                            errorMessageLower.contains('header');
    
    final hasNotFoundKeyword = errorMessageLower.contains('찾지 못') ||
                               errorMessageLower.contains('찾을 수 없') ||
                               errorMessageLower.contains('not found') ||
                               errorMessageLower.contains('cannot find') ||
                               errorMessageLower.contains('failed to find');
    
    final isHeaderError = hasHeaderKeyword && hasNotFoundKeyword;
    
    // 2. 잘못된 crop 영역 에러 (이미지 방향 문제일 수 있음)
    final isCropError = errorMessageLower.contains('잘못된 crop') ||
                       errorMessageLower.contains('crop 영역') ||
                       errorMessageLower.contains('invalid crop') ||
                       errorMessageLower.contains('crop area');
    
    // 3. 이미지 처리 관련 에러들
    final isImageProcessingError = errorMessageLower.contains('이미지 처리') ||
                                   errorMessageLower.contains('image processing') ||
                                   (errorMessageLower.contains('ocr') && 
                                    (errorMessageLower.contains('실패') || 
                                     errorMessageLower.contains('failed') ||
                                     errorMessageLower.contains('오류')));
    
    // 4. 약품 정보 추출 실패 에러 (OCR_EMPTY_RESULT 등 - 이미지 방향 문제일 수 있음)
    final isExtractionError = errorMessageLower.contains('약품 정보를 추출하지 못') ||
                             errorMessageLower.contains('약품 정보 추출') ||
                             errorMessageLower.contains('추출하지 못') ||
                             errorMessageLower.contains('extract') && 
                             (errorMessageLower.contains('failed') ||
                              errorMessageLower.contains('실패') ||
                              errorMessageLower.contains('못')) ||
                             errorMessageLower.contains('empty result') ||
                             errorMessageLower.contains('ocr_empty_result');
    
    final shouldRetry = isHeaderError || isCropError || isImageProcessingError || isExtractionError;
    
    debugPrint('🔍 [약봉투 에러 감지] 헤더 키워드 포함: $hasHeaderKeyword');
    debugPrint('🔍 [약봉투 에러 감지] 찾지 못 키워드 포함: $hasNotFoundKeyword');
    debugPrint('🔍 [약봉투 에러 감지] 헤더 에러 여부: $isHeaderError');
    debugPrint('🔍 [약봉투 에러 감지] Crop 에러 여부: $isCropError');
    debugPrint('🔍 [약봉투 에러 감지] 이미지 처리 에러 여부: $isImageProcessingError');
    debugPrint('🔍 [약봉투 에러 감지] 추출 실패 에러 여부: $isExtractionError');
    debugPrint('🔍 [약봉투 에러 감지] 최종 회전 재시도 여부: $shouldRetry');
    
    return shouldRetry;
  }

  Future<void> _analyzeDrugbag({int rotationAttempt = 0}) async {
    if (_selectedImage == null) {
      await _announce("먼저 약봉투 이미지를 선택해주세요.");
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _ocrResult = null;
    });

    if (rotationAttempt == 0) {
      await _announce("약봉투 이미지를 분석 중입니다. 잠시만 기다려주세요.");
    } else {
      await _announce("이미지를 회전하여 다시 분석 중입니다. ${rotationAttempt}번째 시도입니다.");
    }

    File? imageToAnalyze = _selectedImage!;
    File? tempRotatedFile;

    try {
      // 회전이 필요한 경우 임시 파일 생성
      if (rotationAttempt > 0) {
        debugPrint('🔄 [약봉투 분석] ${rotationAttempt}번째 회전 시도 시작 (${rotationAttempt * 90}도)');
        tempRotatedFile = await _rotateImage(_selectedImage!, rotationAttempt * 90);
        if (tempRotatedFile != null) {
          imageToAnalyze = tempRotatedFile;
          debugPrint('✅ [약봉투 분석] 회전된 이미지로 분석 시작');
        } else {
          debugPrint('❌ [약봉투 분석] 이미지 회전 실패, 원본 이미지로 분석');
        }
      } else {
        debugPrint('📸 [약봉투 분석] 원본 이미지로 분석 시작');
      }

      final result = await _prescriptionService.uploadDrugbagOcr(
        imageFile: imageToAnalyze,
        expectedCount: _expectedCount,
      );
      debugPrint('✅ [약봉투 분석] 분석 성공: $result');

      // 임시 파일 정리
      if (tempRotatedFile != null && await tempRotatedFile.exists()) {
        await tempRotatedFile.delete();
      }

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _ocrResult = result;
      });

      // 결과 화면을 먼저 표시
      _showResults();
      
      // 진동과 음성 안내는 비동기로 처리 (결과 표시를 막지 않음)
      Future.microtask(() async {
        await _vibrate(duration: 200);
        final totalItems = result['total_items'] ?? 0;
        await _announce(
          "분석이 완료되었습니다. "
          "총 $totalItems개의 약이 인식되었습니다. "
          "결과를 확인하고 알약 촬영을 진행할 수 있습니다.",
        );
      });
    } on DioException catch (e) {
      // 임시 파일 정리
      if (tempRotatedFile != null && await tempRotatedFile.exists()) {
        await tempRotatedFile.delete();
      }

      if (!mounted) return;
      
      final code = e.response?.statusCode;
      final responseData = e.response?.data;
      
      debugPrint('❌ [약봉투 에러] 상태 코드: $code');
      debugPrint('❌ [약봉투 에러] 응답 데이터: $responseData');
      debugPrint('❌ [약봉투 에러] 현재 회전 시도 횟수: $rotationAttempt');
      
      // 회전 재시도가 필요한 에러인지 확인
      final shouldRetry = _shouldRetryWithRotation(responseData);
      debugPrint('❌ [약봉투 에러] 회전 재시도 필요 여부: $shouldRetry');
      
      // 회전 재시도가 필요하고 아직 3번 미만 시도한 경우 회전 재시도 (총 4번: 원본 + 90도 + 180도 + 270도)
      if (shouldRetry && rotationAttempt < 3) {
        debugPrint('🔄 [약봉투 재시도] 회전 재시도 시작: ${rotationAttempt + 1}번째 시도 (${(rotationAttempt + 1) * 90}도 회전)');
        
        // 다음 회전 시도 (500ms 대기 후)
        await Future.delayed(const Duration(milliseconds: 500));
        await _analyzeDrugbag(rotationAttempt: rotationAttempt + 1);
        return; // 여기서 리턴하므로 아래 오류 다이얼로그는 실행되지 않음
      }
      
      // 회전 재시도가 필요하지 않거나, 모든 회전 시도가 실패한 경우 오류 다이얼로그 표시
      if (shouldRetry && rotationAttempt >= 3) {
        debugPrint('❌ [약봉투 재시도] 모든 회전 시도 실패 (총 4번 시도 완료)');
      }
      
      String errorMsg = "약봉투 분석 중 오류가 발생했습니다.";
      
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        errorMsg = "네트워크 시간 초과. 다시 시도해주세요.";
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = "서버에 연결할 수 없습니다. 네트워크를 확인해주세요.";
      } else if (e.type == DioExceptionType.cancel) {
        errorMsg = "요청이 취소되었습니다.";
      } else if (code == 400) {
        errorMsg = "이미지 형식이 올바르지 않습니다.";
      } else if (code == 422) {
        final hint = (responseData is Map && responseData['message'] != null)
            ? responseData['message'].toString()
            : responseData?.toString();
        errorMsg = "요청 검증 실패: ${hint ?? '이미지 형식을 확인해주세요'}";
      } else if (code == 500) {
        errorMsg = "서버 내부 오류가 발생했습니다. 잠시 후 다시 시도해주세요.";
      } else if (code == 502) {
        final errorMsgDetail = responseData is Map 
            ? (responseData['error']?['message'] ?? responseData['message'] ?? '외부 서비스 연결 실패')
            : '서버가 외부 서비스에 연결할 수 없습니다';
        errorMsg = "서버 연결 오류: $errorMsgDetail";
      } else if (code == 503) {
        errorMsg = "서버가 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해주세요.";
      } else if (code != null) {
        errorMsg = "서버 오류 ($code). 다시 시도해주세요.";
      }

      setState(() {
        _isProcessing = false;
      });

      // 오류 다이얼로그 표시
      _showErrorDialog(errorMsg);
    } catch (e) {
      // 임시 파일 정리
      if (tempRotatedFile != null && await tempRotatedFile.exists()) {
        await tempRotatedFile.delete();
      }

      if (!mounted) return;
      
      String errorMsg = "알 수 없는 오류가 발생했습니다.";
      if (e.toString().contains('Client')) {
        errorMsg = "클라이언트 오류가 발생했습니다. 이미지 파일을 확인해주세요.";
      } else if (e.toString().contains('Socket') || e.toString().contains('Network')) {
        errorMsg = "네트워크 연결 오류가 발생했습니다. 인터넷 연결을 확인해주세요.";
      }
      
      setState(() {
        _isProcessing = false;
      });

      // 오류 다이얼로그 표시
      _showErrorDialog(errorMsg);
    }
  }

  /// 오류 다이얼로그 표시
  Future<void> _showErrorDialog(String errorMsg) async {
    if (!mounted) return;

    await _announce(errorMsg);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Consumer<ThemeService>(
          builder: (context, theme, child) {
            return AlertDialog(
              backgroundColor: theme.backgroundColor,
              title: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red[600],
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "오류가 발생했습니다",
                      style: theme.titleStyle.copyWith(
                        fontSize: 22 * theme.fontScale,
                        color: Colors.red[600],
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                errorMsg,
                style: theme.bodyTextStyle.copyWith(
                  fontSize: 16 * theme.fontScale,
                ),
              ),
              actions: [
                AccessibleButton(
                  label: "다시 촬영하기",
                  icon: Icons.camera_alt,
                  hint: "약봉투 촬영 화면으로 돌아갑니다",
                  onPressed: () {
                    Navigator.of(context).pop(); // 다이얼로그 닫기
                    // 촬영 화면으로 이동
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DrugbagCameraScreen(),
                      ),
                    ).then((result) {
                      // 촬영 결과가 있으면 이미지 선택 처리
                      if (result is File) {
                        setState(() {
                          _selectedImage = result;
                          _errorMessage = null;
                          _ocrResult = null;
                        });
                        _vibrate(duration: 100);
                        _announce("이미지가 선택되었습니다. 분석하기 버튼을 눌러주세요.");
                      }
                    });
                  },
                  height: 50,
                ),
                const SizedBox(height: 12),
                AccessibleButton(
                  label: "갤러리에서 업로드",
                  icon: Icons.photo_library,
                  hint: "갤러리에서 약봉투 이미지를 선택합니다",
                  onPressed: () {
                    Navigator.of(context).pop(); // 다이얼로그 닫기
                    _pickImage(ImageSource.gallery);
                  },
                  height: 50,
                  backgroundColor: theme.buttonColor.withOpacity(0.8),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 알약 개수 선택 시트 (처방전과 동일한 UI)
  void _showPillCountSheet(String prescriptionId, int defaultCount) {
    if (!mounted) return;

    final maxCount = defaultCount > 0 ? defaultCount : 10; // 최대 10개로 제한
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
        return Consumer<ThemeService>(
          builder: (context, theme, child) {
            return Container(
              decoration: BoxDecoration(
                color: theme.backgroundColor,
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
                          style: theme.titleStyle.copyWith(
                            fontSize: 24 * theme.fontScale,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "이번에 인식할 알약 사진 개수를 선택해주세요. "
                          "기본값은 약봉투에서 인식된 약 개수입니다.",
                          style: theme.subtitleTextStyle.copyWith(
                            fontSize: 16 * theme.fontScale,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
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
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  size: 30 * theme.fontScale,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              "$currentCount 개",
                              style: theme.titleStyle.copyWith(
                                fontSize: 22 * theme.fontScale,
                              ),
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
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  size: 30 * theme.fontScale,
                                  color: theme.primaryColor,
                                ),
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
                                  side: BorderSide(color: theme.primaryColor),
                                  foregroundColor: theme.textColor,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: Text(
                                  "취소",
                                  style: theme.buttonTextStyle.copyWith(
                                    fontSize: 18 * theme.fontScale,
                                    color: theme.textColor,
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
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PillCapturePage(
                                        prescriptionId: prescriptionId,
                                        totalCount: currentCount,
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  backgroundColor: theme.buttonColor,
                                  foregroundColor: theme.buttonTextColor,
                                ),
                                child: Text(
                                  "알약 촬영 시작",
                                  style: theme.buttonTextStyle.copyWith(
                                    fontSize: 18 * theme.fontScale,
                                  ),
                                ),
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
      },
    );
  }

  /// 보관함에 저장 다이얼로그
  Future<void> _showSaveDialog(BuildContext context, String prescriptionId, ThemeService theme, VoidCallback? onSaved) async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return AlertDialog(
            backgroundColor: theme.backgroundColor,
            title: Text(
              '약봉투 저장',
              style: theme.titleStyle.copyWith(fontSize: 24 * theme.fontScale),
            ),
            content: Text(
              '이 약봉투 분석 결과를 보관함에 저장하시겠습니까?\n나중에 기록함에서 다시 불러올 수 있습니다.',
              style: theme.bodyTextStyle.copyWith(fontSize: 18 * theme.fontScale),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: Text(
                  '취소',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.textColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('save'),
                child: Text(
                  '저장하기',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (action == 'save') {
      await _saveToPrescriptionBox(prescriptionId, theme);
      // 저장 완료 후 콜백 호출하여 모달 상태 업데이트
      if (onSaved != null) {
        onSaved();
      }
    }
  }

  /// 보관함에 저장
  Future<void> _saveToPrescriptionBox(String prescriptionId, ThemeService theme) async {
    try {
      if (theme.isVoiceGuideEnabled) {
        await _announce("보관함에 저장 중입니다.");
      }

      await _prescriptionService.saveTemplate(prescriptionId);

      if (!mounted) return;

      if (theme.isVoiceGuideEnabled) {
        await _announce("보관함에 저장되었습니다.");
      }
      await _vibrate(duration: 200);

      setState(() {
        _isSaved = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '보관함에 저장되었습니다.',
              style: TextStyle(fontSize: 16 * theme.fontScale),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (theme.isVoiceGuideEnabled) {
        await _announce("저장에 실패했습니다.");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '저장에 실패했습니다: ${e.toString()}',
              style: TextStyle(fontSize: 16 * theme.fontScale),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 닫기 버튼 처리
  Future<void> _handleClose(BuildContext context, String? prescriptionId, ThemeService theme) async {
    if (_isSaved) {
      Navigator.pop(context);
      return;
    }

    // 저장되지 않은 경우 저장 여부 묻기
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return AlertDialog(
            backgroundColor: theme.backgroundColor,
            title: Text(
              '약봉투 저장',
              style: theme.titleStyle.copyWith(fontSize: 24 * theme.fontScale),
            ),
            content: Text(
              '이 약봉투 분석 결과를 보관함에 저장하시겠습니까?\n나중에 기록함에서 다시 불러올 수 있습니다.',
              style: theme.bodyTextStyle.copyWith(fontSize: 18 * theme.fontScale),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop('exit');
                  if (theme.isVoiceGuideEnabled) {
                    await _announce("저장하지 않고 닫습니다.");
                  }
                },
                child: Text(
                  '저장 안 함',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.textColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop('save');
                  if (theme.isVoiceGuideEnabled) {
                    await _announce("저장하기를 선택하셨습니다.");
                  }
                },
                child: Text(
                  '저장하기',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (action == 'save' && prescriptionId != null) {
      await _saveToPrescriptionBox(prescriptionId, theme);
      if (mounted) {
        Navigator.pop(context);
      }
    } else if (action == 'exit') {
      Navigator.pop(context);
    }
  }

  void _showResults() {
    if (_ocrResult == null) return;

    final prescriptionId = _ocrResult!['prescription_id'] as String?;
    final totalItems = _ocrResult!['total_items'] as int? ?? 0;
    final results = _ocrResult!['results'] as List<dynamic>? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // 헤더
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.primaryColor.withOpacity(0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          label: "약봉투 분석 결과. 총 $totalItems개의 약이 인식되었습니다.",
                          child: Text(
                            "약봉투 분석 결과",
                            style: theme.titleStyle.copyWith(
                              fontSize: 26 * theme.fontScale,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        tooltip: "닫기",
                      ),
                    ],
                  ),
                ),
                // 결과 리스트
                Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Semantics(
                            label: "인식된 약이 없습니다",
                            child: Text(
                                "인식된 약이 없습니다",
                                style: theme.bodyTextStyle.copyWith(
                                  fontSize: 20 * theme.fontScale,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final item = results[index] as Map<String, dynamic>;
                            final itemName = item['itemName'] as String? ?? '이름 없음';
                            final itemSeq = item['itemSeq'] as String?;
                            final totalCount = item['totalCount'] as String?;
                            final onceDose = item['onceDose'] as String?;
                            final dayDose = item['dayDose'] as String?;
                            final totalDose = item['totalDose'] as String?;

                            return Semantics(
                              button: itemSeq != null && itemSeq.isNotEmpty,
                              label: "${index + 1}번 약: $itemName. "
                                  "${totalCount != null ? '총 $totalCount개. ' : ''}"
                                  "${onceDose != null ? '1회 $onceDose개. ' : ''}"
                                  "${dayDose != null ? '1일 $dayDose회. ' : ''}"
                                  "${totalDose != null ? '총 $totalDose일. ' : ''}"
                                  "${itemSeq != null && itemSeq.isNotEmpty ? '탭하면 상세 정보를 확인할 수 있습니다.' : ''}",
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                color: theme.backgroundColor.withOpacity(0.1),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: itemSeq != null && itemSeq.isNotEmpty
                                        ? () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => DrugDetailScreen(
                                                  initialDrugInfo: {'itemSeq': itemSeq},
                                                ),
                                              ),
                                            );
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(12),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      leading: Icon(
                                        Icons.medication,
                                        color: theme.primaryColor,
                                        size: 32,
                                      ),
                                      title: Text(
                                        itemName,
                                        style: theme.bodyTextStyle.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20 * theme.fontScale,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (totalCount != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                "총 개수: $totalCount",
                                                style: theme.subtitleTextStyle.copyWith(
                                                  fontSize: 18 * theme.fontScale,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          if (onceDose != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                "1회 투약량: $onceDose",
                                                style: theme.subtitleTextStyle.copyWith(
                                                  fontSize: 18 * theme.fontScale,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          if (dayDose != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                "1일 투여 횟수: $dayDose",
                                                style: theme.subtitleTextStyle.copyWith(
                                                  fontSize: 18 * theme.fontScale,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          if (totalDose != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                "총 투약 일수: $totalDose",
                                                style: theme.subtitleTextStyle.copyWith(
                                                  fontSize: 18 * theme.fontScale,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                      ),
                                      trailing: itemSeq != null && itemSeq.isNotEmpty
                                          ? Icon(
                                              Icons.arrow_forward_ios,
                                              color: theme.primaryColor,
                                              size: 20,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // 하단 버튼
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.primaryColor.withOpacity(0.2)),
                    ),
                  ),
                  child: StatefulBuilder(
                    builder: (context, setModalState) {
                      return Column(
                        children: [
                          AccessibleButton(
                            label: "알약 촬영하기",
                            icon: Icons.camera_alt,
                            hint: "인식된 약들을 촬영하여 확인합니다",
                            onPressed: prescriptionId != null
                                ? () {
                                    Navigator.pop(context);
                                    _showPillCountSheet(prescriptionId, totalItems);
                                  }
                                : () {},
                          ),
                          const SizedBox(height: 12),
                          if (!_isSaved)
                            AccessibleButton(
                              label: "보관함에 저장",
                              icon: Icons.save,
                              hint: "약봉투 분석 결과를 보관함에 저장합니다",
                              onPressed: prescriptionId != null
                                  ? () async {
                                      await _showSaveDialog(
                                        context,
                                        prescriptionId,
                                        theme,
                                        () {
                                          // 저장 완료 후 모달 상태 업데이트
                                          setModalState(() {});
                                        },
                                      );
                                    }
                                  : () {},
                              height: 50,
                              backgroundColor: theme.buttonColor.withOpacity(0.8),
                            ),
                          if (!_isSaved) const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => _handleClose(context, prescriptionId, theme),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              side: BorderSide(color: theme.primaryColor),
                            ),
                            child: Text(
                              _isSaved ? "닫기" : "저장하지 않고 닫기",
                              style: theme.bodyTextStyle.copyWith(color: theme.primaryColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: "약봉투 인식",
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                container: true,
                label: "약봉투 인식 화면",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // 설명
                  Semantics(
                    label: "약봉투 이미지를 업로드하면 OCR로 약 목록을 추출합니다",
                    child: Text(
                      "약봉투 이미지를 업로드하면 OCR로 약 목록을 추출합니다",
                      style: theme.bodyTextStyle.copyWith(
                        fontSize: 20 * theme.fontScale,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 이미지 미리보기
                  if (_selectedImage != null)
                    Semantics(
                      label: "선택된 약봉투 이미지",
                      image: true,
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: theme.backgroundColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.primaryColor, width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Semantics(
                      label: "이미지가 선택되지 않았습니다",
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: theme.backgroundColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.primaryColor.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_outlined,
                                size: 48,
                                color: theme.textColor.withOpacity(0.5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "이미지를 선택해주세요",
                                style: theme.subtitleTextStyle.copyWith(
                                  fontSize: 18 * theme.fontScale,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // 이미지 선택 버튼
                  Row(
                    children: [
                      Expanded(
                        child: AccessibleButton(
                          label: "카메라로 촬영",
                          icon: Icons.camera_alt,
                          hint: "카메라로 약봉투를 촬영합니다",
                          onPressed: _isProcessing ? () {} : () => _pickImage(ImageSource.camera),
                          height: 56,
                          textStyle: theme.buttonTextStyle.copyWith(
                            fontSize: 16 * theme.fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AccessibleButton(
                          label: "갤러리에서 선택",
                          icon: Icons.photo_library,
                          hint: "갤러리에서 약봉투 이미지를 선택합니다",
                          onPressed: _isProcessing ? () {} : () => _pickImage(ImageSource.gallery),
                          height: 56,
                          backgroundColor: theme.buttonColor.withOpacity(0.8),
                          textStyle: theme.buttonTextStyle.copyWith(
                            fontSize: 16 * theme.fontScale,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 분석 버튼
                  AccessibleButton(
                    label: "분석하기",
                    icon: Icons.search,
                    hint: "선택한 약봉투 이미지를 분석합니다",
                    onPressed: (_selectedImage != null && !_isProcessing)
                        ? _analyzeDrugbag
                        : () {},
                    height: 56,
                  ),

                  const SizedBox(height: 16),

                  // 로딩 표시
                  if (_isProcessing)
                    Semantics(
                      liveRegion: true,
                      label: "약봉투 이미지를 분석 중입니다",
                      child: const LoadingWidget(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

