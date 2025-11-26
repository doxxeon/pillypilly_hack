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
import 'prescription_camera_screen.dart';
import 'prescription_result_modal.dart';

class PrescriptionOcrScreen extends StatefulWidget {
  final ImageSource? initialSource;
  
  const PrescriptionOcrScreen({
    Key? key,
    this.initialSource,
  }) : super(key: key);

  @override
  State<PrescriptionOcrScreen> createState() => _PrescriptionOcrScreenState();
}

class _PrescriptionOcrScreenState extends State<PrescriptionOcrScreen> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();
  final PrescriptionService _prescriptionService = PrescriptionService();
  
  File? _selectedImage;
  bool _isProcessing = false;
  String? _errorMessage;
  Map<String, dynamic>? _ocrResult;

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
        "처방전 인식 화면입니다. "
        "처방전 이미지를 촬영하거나 갤러리에서 선택하세요.",
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
        // 카메라 화면으로 이동
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PrescriptionCameraScreen(),
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
      debugPrint('🔄 [처방전 회전] 이미지 회전 시작: ${degrees}도');
      final bytes = await imageFile.readAsBytes();
      debugPrint('🔄 [처방전 회전] 원본 이미지 크기: ${bytes.length} bytes');
      
      // EXIF 방향 정보를 이미지에 적용하고 제거 (bakeOrientation)
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) {
        debugPrint('❌ [처방전 회전] 이미지 디코딩 실패');
        return null;
      }
      
      // EXIF 방향 정보 적용 (이미 회전된 경우를 고려)
      final normalizedImage = img.bakeOrientation(decodedImage);
      debugPrint('🔄 [처방전 회전] EXIF 정규화 후 이미지 크기: ${normalizedImage.width}x${normalizedImage.height}');
      
      // 추가 회전 적용
      final rotatedImage = img.copyRotate(normalizedImage, angle: degrees);
      debugPrint('🔄 [처방전 회전] 회전된 이미지 크기: ${rotatedImage.width}x${rotatedImage.height}');
      
      // EXIF 없이 새로 인코딩 (quality 95로 고화질 유지)
      final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotatedImage, quality: 95));
      debugPrint('🔄 [처방전 회전] 회전된 이미지 바이트 크기: ${rotatedBytes.length} bytes');
      
      // 임시 파일 생성
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/prescription_rotated_${DateTime.now().millisecondsSinceEpoch}_$degrees.jpg');
      await tempFile.writeAsBytes(rotatedBytes);
      
      debugPrint('✅ [처방전 회전] 회전된 이미지 저장 완료: ${tempFile.path}');
      return tempFile;
    } catch (e, stackTrace) {
      debugPrint('❌ [처방전 회전] 이미지 회전 오류: $e');
      debugPrint('❌ [처방전 회전] 스택 트레이스: $stackTrace');
      return null;
    }
  }

  /// 회전 재시도가 필요한 에러인지 확인 (헤더 에러, crop 영역 에러 등)
  bool _shouldRetryWithRotation(dynamic responseData) {
    if (responseData == null) {
      debugPrint('🔍 [처방전 에러 감지] responseData가 null입니다');
      return false;
    }
    
    debugPrint('🔍 [처방전 에러 감지] responseData 타입: ${responseData.runtimeType}');
    debugPrint('🔍 [처방전 에러 감지] responseData 전체 내용: $responseData');
    
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
    debugPrint('🔍 [처방전 에러 감지] 추출된 에러 메시지: $errorMessage');
    debugPrint('🔍 [처방전 에러 감지] 소문자 변환: $errorMessageLower');
    
    // 백엔드에서 이미 모든 회전 시도를 했다는 신호가 있으면 프론트엔드에서 재시도하지 않음
    if (errorMessageLower.contains('모든 회전 시도 실패') || 
        errorMessageLower.contains('all rotation attempts failed')) {
      debugPrint('🔍 [처방전 에러 감지] 백엔드에서 이미 모든 회전 시도 완료 - 프론트엔드 재시도 안 함');
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
    
    debugPrint('🔍 [처방전 에러 감지] 헤더 키워드 포함: $hasHeaderKeyword');
    debugPrint('🔍 [처방전 에러 감지] 찾지 못 키워드 포함: $hasNotFoundKeyword');
    debugPrint('🔍 [처방전 에러 감지] 헤더 에러 여부: $isHeaderError');
    debugPrint('🔍 [처방전 에러 감지] Crop 에러 여부: $isCropError');
    debugPrint('🔍 [처방전 에러 감지] 이미지 처리 에러 여부: $isImageProcessingError');
    debugPrint('🔍 [처방전 에러 감지] 추출 실패 에러 여부: $isExtractionError');
    debugPrint('🔍 [처방전 에러 감지] 최종 회전 재시도 여부: $shouldRetry');
    
    return shouldRetry;
  }

  Future<void> _analyzePrescription({int rotationAttempt = 0}) async {
    if (_selectedImage == null) {
      await _announce("먼저 처방전 이미지를 선택해주세요.");
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _ocrResult = null;
    });

    if (rotationAttempt == 0) {
      await _announce("처방전 이미지를 분석 중입니다. 잠시만 기다려주세요.");
    } else {
      await _announce("이미지를 회전하여 다시 분석 중입니다. ${rotationAttempt}번째 시도입니다.");
    }

    File? imageToAnalyze = _selectedImage!;
    File? tempRotatedFile;

    try {
      // 회전이 필요한 경우 임시 파일 생성
      if (rotationAttempt > 0) {
        debugPrint('🔄 [분석] ${rotationAttempt}번째 회전 시도 시작 (${rotationAttempt * 90}도)');
        tempRotatedFile = await _rotateImage(_selectedImage!, rotationAttempt * 90);
        if (tempRotatedFile != null) {
          imageToAnalyze = tempRotatedFile;
          debugPrint('✅ [분석] 회전된 이미지로 분석 시작');
        } else {
          debugPrint('❌ [분석] 이미지 회전 실패, 원본 이미지로 분석');
        }
      } else {
        debugPrint('📸 [분석] 원본 이미지로 분석 시작');
      }

      final result = await _prescriptionService.uploadPrescription(imageToAnalyze);
      debugPrint('✅ [분석] 분석 성공: $result');

      // 임시 파일 정리
      if (tempRotatedFile != null && await tempRotatedFile.exists()) {
        await tempRotatedFile.delete();
      }

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _ocrResult = result;
      });

      debugPrint('✅ [처방전 분석] 결과 저장 완료: prescription_id=${result['prescription_id']}, total_items=${result['total_items']}, results=${result['results']?.length ?? 0}');

      // 결과 화면을 다음 프레임에서 표시 (렌더링 사이클 대기)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('✅ [처방전 분석] 결과 화면 표시 시작');
          _showResults();
        }
      });
      
      // 진동과 음성 안내는 비동기로 처리 (결과 표시를 막지 않음)
      Future.microtask(() async {
        await _vibrate(duration: 200);
        final totalCount = result['total_items'] as int? ?? 0;
        await _announce(
          "분석이 완료되었습니다. "
          "총 $totalCount개의 약이 인식되었습니다. "
          "결과를 확인할 수 있습니다.",
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
      
      debugPrint('❌ [에러] 상태 코드: $code');
      debugPrint('❌ [에러] 응답 데이터: $responseData');
      debugPrint('❌ [에러] 현재 회전 시도 횟수: $rotationAttempt');
      
      // 회전 재시도가 필요한 에러인지 확인
      final shouldRetry = _shouldRetryWithRotation(responseData);
      debugPrint('❌ [처방전 에러] 회전 재시도 필요 여부: $shouldRetry');
      
      // 회전 재시도가 필요하고 아직 3번 미만 시도한 경우 회전 재시도 (총 4번: 원본 + 90도 + 180도 + 270도)
      if (shouldRetry && rotationAttempt < 3) {
        debugPrint('🔄 [재시도] 회전 재시도 시작: ${rotationAttempt + 1}번째 시도 (${(rotationAttempt + 1) * 90}도 회전)');
        
        // 다음 회전 시도 (500ms 대기 후)
        await Future.delayed(const Duration(milliseconds: 500));
        await _analyzePrescription(rotationAttempt: rotationAttempt + 1);
        return; // 여기서 리턴하므로 아래 오류 다이얼로그는 실행되지 않음
      }
      
      // 회전 재시도가 필요하지 않거나, 모든 회전 시도가 실패한 경우 오류 다이얼로그 표시
      if (shouldRetry && rotationAttempt >= 3) {
        debugPrint('❌ [처방전 재시도] 모든 회전 시도 실패 (총 4번 시도 완료)');
      }
      
      String errorMsg = "처방전 분석 중 오류가 발생했습니다.";
      
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
                  hint: "처방전 촬영 화면으로 돌아갑니다",
                  onPressed: () {
                    Navigator.of(context).pop(); // 다이얼로그 닫기
                    // 촬영 화면으로 이동
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrescriptionCameraScreen(),
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
                  hint: "갤러리에서 처방전 이미지를 선택합니다",
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

  void _showResults() {
    if (_ocrResult == null) {
      debugPrint('❌ [처방전 결과] _ocrResult가 null입니다.');
      return;
    }

    final prescriptionId = _ocrResult!['prescription_id'] as String?;
    final totalItems = _ocrResult!['total_items'] as int? ?? 0;
    final results = _ocrResult!['results'] as List<dynamic>? ?? [];

    debugPrint('✅ [처방전 결과] prescriptionId: $prescriptionId, totalItems: $totalItems, results.length: ${results.length}');

    if (prescriptionId == null || prescriptionId.isEmpty) {
      debugPrint('❌ [처방전 결과] prescriptionId가 없습니다.');
      _announce("처방전 ID를 찾을 수 없습니다.");
      return;
    }

    // 약 봉투와 동일한 모달 UI로 결과 표시
    debugPrint('✅ [처방전 결과] 모달 표시 시작');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<ThemeService>(
        builder: (context, theme, child) {
          debugPrint('✅ [처방전 결과] 모달 빌더 실행');
          return PrescriptionResultModal(
            prescriptionId: prescriptionId,
            totalItems: totalItems,
            initialResults: results,
            theme: theme,
          );
        },
      ),
    ).then((_) {
      debugPrint('✅ [처방전 결과] 모달이 닫혔습니다.');
    }).catchError((e) {
      debugPrint('❌ [처방전 결과] 모달 표시 오류: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: "처방전 인식",
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                container: true,
                label: "처방전 인식 화면",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // 설명
                  Semantics(
                    label: "처방전 이미지를 업로드하면 OCR로 약 목록을 추출합니다",
                    child: Text(
                      "처방전 이미지를 업로드하면 OCR로 약 목록을 추출합니다",
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
                      label: "선택된 처방전 이미지",
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
                          hint: "카메라로 처방전을 촬영합니다",
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
                          hint: "갤러리에서 처방전 이미지를 선택합니다",
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
                    hint: "선택한 처방전 이미지를 분석합니다",
                    onPressed: (_selectedImage != null && !_isProcessing)
                        ? _analyzePrescription
                        : () {},
                    height: 56,
                  ),

                  const SizedBox(height: 16),

                  // 로딩 표시
                  if (_isProcessing)
                    Semantics(
                      liveRegion: true,
                      label: "처방전 이미지를 분석 중입니다",
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

