import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';

import '../../services/theme_service.dart';
import '../../services/prescription_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import '../../widgets/loading_widget.dart';

class BoxExpScreen extends StatefulWidget {
  const BoxExpScreen({super.key});

  @override
  State<BoxExpScreen> createState() => _BoxExpScreenState();
}

class _BoxExpScreenState extends State<BoxExpScreen> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();
  final PrescriptionService _prescriptionService = PrescriptionService();

  File? _firstImage;
  File? _secondImage;
  bool _isLoading = false;
  String? _errorMessage;
  
  // 첫 번째 면 결과
  DateTime? _firstExpiryDate;
  String? _firstMessage;
  String? _firstStatus;
  
  // 두 번째 면 결과
  DateTime? _secondExpiryDate;
  String? _secondMessage;
  String? _secondStatus;
  
  int _captureStep = 0; // 0: 시작, 1: 첫 번째 촬영 완료, 2: 두 번째 촬영 완료

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _captureFirstSide(ThemeService theme) async {
    // 첫 번째 면 촬영 안내
    if (theme.isVoiceGuideEnabled) {
      await _tts.speak(
        "유통기한 인식을 위해 약 상자의 양쪽 가장 좁은 면을 모두 촬영합니다. "
        "먼저 첫 번째 면을 촬영합니다. "
        "약 상자를 손에 들고, 가장 좁은 면 중 하나를 찾아주세요. "
        "'사용기한', 'EXP', '유통기한' 같은 텍스트를 인식합니다. "
        "만약 결과가 나오지 않으면 다른 면으로 다시 촬영해주세요. "
        "약 상자를 약 30센티미터 정도 떨어뜨려서 촬영하면 인식이 더 잘 됩니다. "
        "너무 가까이 촬영하지 마세요. "
        "카메라가 열리면 화면 중앙에 유통기한 텍스트가 오도록 약 상자를 움직여주세요. "
        "준비되면 촬영 버튼을 눌러주세요.",
      );
      await Future.delayed(const Duration(seconds: 2));
    }

    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    
    if (picked == null) {
      if (theme.isVoiceGuideEnabled) {
        await _tts.speak("첫 번째 면 촬영이 취소되었습니다.");
      }
      return;
    }

    setState(() {
      _firstImage = File(picked.path);
      _captureStep = 1;
    });

    Vibration.vibrate(duration: 120);

    if (theme.isVoiceGuideEnabled) {
      await _tts.speak("첫 번째 면이 촬영되었습니다.");
    }
    
    // 자동으로 넘어가지 않음 - 사용자가 버튼을 눌러야 함
  }

  Future<void> _captureSecondSide(ThemeService theme) async {
    // 두 번째 면 촬영 안내
    if (theme.isVoiceGuideEnabled) {
      await _tts.speak(
        "이제 반대편 작은 면(두번째 면)을 촬영 해주세요. "
        "'사용기한', 'EXP', '유통기한' 같은 텍스트를 인식합니다. "
        "만약 결과가 나오지 않으면 다른 면으로 다시 촬영해주세요. "
        "준비가되면 촬영하기 버튼을 눌러주세요.",
      );
      await Future.delayed(const Duration(seconds: 1));
    }

    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    
    if (picked == null) {
      if (theme.isVoiceGuideEnabled) {
        await _tts.speak("두 번째 면 촬영이 취소되었습니다. 다시 시작하려면 촬영하기 버튼을 눌러주세요.");
      }
      setState(() {
        _firstImage = null;
        _captureStep = 0;
      });
      return;
    }

    setState(() {
      _secondImage = File(picked.path);
      _captureStep = 2;
      _isLoading = true;
      _errorMessage = null;
    });

    Vibration.vibrate(duration: 120);

    if (theme.isVoiceGuideEnabled) {
      await _tts.speak("두 번째 면도 촬영되었습니다. 양쪽 면의 유통기한을 확인하고 있습니다. 잠시만 기다려주세요.");
    }

    await _checkBothSides(theme);
  }

  Future<void> _checkBothSides(ThemeService theme) async {
    if (_firstImage == null || _secondImage == null) return;

    try {
      // 두 이미지를 동시에 서버에 전송
      final results = await Future.wait([
        _prescriptionService.checkExpiryDate(_firstImage!),
        _prescriptionService.checkExpiryDate(_secondImage!),
      ]);

      final firstResult = results[0];
      final secondResult = results[1];

      // 첫 번째 면 결과 처리
      final firstStatus = firstResult['status']?.toString() ?? '';
      final firstMessage = firstResult['message']?.toString() ?? '';
      final firstExpiryDateStr = firstResult['expiry_date']?.toString();

      DateTime? firstDate;
      if (firstExpiryDateStr != null && firstStatus == 'SUCCESS') {
        final dateParts = firstExpiryDateStr.split('-');
        if (dateParts.length == 3) {
          firstDate = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          );
        }
      }

      // 두 번째 면 결과 처리
      final secondStatus = secondResult['status']?.toString() ?? '';
      final secondMessage = secondResult['message']?.toString() ?? '';
      final secondExpiryDateStr = secondResult['expiry_date']?.toString();

      DateTime? secondDate;
      if (secondExpiryDateStr != null && secondStatus == 'SUCCESS') {
        final dateParts = secondExpiryDateStr.split('-');
        if (dateParts.length == 3) {
          secondDate = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          );
        }
      }

      setState(() {
        _firstExpiryDate = firstDate;
        _firstMessage = firstMessage;
        _firstStatus = firstStatus;
        _secondExpiryDate = secondDate;
        _secondMessage = secondMessage;
        _secondStatus = secondStatus;
        _isLoading = false;
        _errorMessage = null;
      });

      // 결과 음성 안내
      if (theme.isVoiceGuideEnabled) {
        String announcement = "양쪽 면의 유통기한 확인이 완료되었습니다. ";
        
        if (firstDate != null) {
          announcement += "첫 번째 면: ${firstDate.year}년 ${firstDate.month}월 ${firstDate.day}일. $firstMessage ";
        } else if (firstStatus == 'NOT_FOUND') {
          announcement += "첫 번째 면에서는 유통기한을 찾을 수 없었습니다. 다른 면으로 다시 촬영해주세요. ";
        }
        
        if (secondDate != null) {
          announcement += "두 번째 면: ${secondDate.year}년 ${secondDate.month}월 ${secondDate.day}일. $secondMessage";
        } else if (secondStatus == 'NOT_FOUND') {
          announcement += "두 번째 면에서는 유통기한을 찾을 수 없었습니다. 다른 면으로 다시 촬영해주세요.";
        }
        
        await _tts.speak(announcement);
      }

      Vibration.vibrate(duration: 180);
    } on DioException catch (e) {
      if (!mounted) return;
      
      final code = e.response?.statusCode;
      String errorMsg = "유통기한 확인 중 오류가 발생했습니다.";
      
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        errorMsg = "네트워크 시간 초과. 다시 시도해주세요.";
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = "서버에 연결할 수 없습니다. 네트워크를 확인해주세요.";
      } else if (code == 400) {
        errorMsg = "이미지 형식이 올바르지 않습니다.";
      } else if (code == 422) {
        errorMsg = "요청 검증 실패. 이미지 파일을 확인해주세요.";
      } else if (code == 500 || code == 502 || code == 503) {
        errorMsg = "서버 오류가 발생했습니다. 잠시 후 다시 시도해주세요.";
      }

      setState(() {
        _isLoading = false;
        _errorMessage = errorMsg;
      });

      if (theme.isVoiceGuideEnabled) {
        await _tts.speak(errorMsg);
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
        _errorMessage = "유통기한 확인 중 오류가 발생했습니다: ${e.toString()}";
      });
      if (theme.isVoiceGuideEnabled) {
        await _tts.speak("유통기한 확인 중 오류가 발생했습니다. 다시 시도해 주세요.");
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '유통기한 인식',
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Semantics(
                    label: '유통기한 인식 화면. 약 상자의 가장 좁은 면 양쪽을 모두 촬영합니다.',
                    hint: '약 상자의 가장 좁은 면 양쪽을 촬영해서 유통기한을 확인합니다.',
                    child: _captureStep == 0
                        ? Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              color: theme.backgroundColor.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.primaryColor,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 48,
                                    color: theme.textColor.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '약 상자의 가장 좁은 면\n양쪽을 모두 촬영해주세요',
                                    textAlign: TextAlign.center,
                                    style: theme.bodyTextStyle.copyWith(
                                      fontSize: 18 * theme.fontScale,
                                      color: theme.textColor.withOpacity(0.7),
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: theme.backgroundColor.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: _firstImage != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: Image.file(
                                            _firstImage!,
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            '첫 번째 면',
                                            style: theme.bodyTextStyle.copyWith(
                                              fontSize: 16 * theme.fontScale,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: theme.backgroundColor.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                  child: _secondImage != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: Image.file(
                                            _secondImage!,
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            '두 번째 면',
                                            style: theme.bodyTextStyle.copyWith(
                                              fontSize: 16 * theme.fontScale,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                  if (_isLoading)
                    const LoadingWidget(
                      message: "양쪽 면의 유통기한을 확인하고 있습니다...",
                    )
                  else if (_errorMessage != null)
                    _buildError(theme)
                  else if (_captureStep == 2 && (_firstExpiryDate != null || _secondExpiryDate != null || _firstStatus == 'NOT_FOUND' || _secondStatus == 'NOT_FOUND'))
                    _buildBothResults(theme)
                  else
                    _buildActionButtons(theme),
                  const SizedBox(height: 24),
                  _buildHelperText(theme),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(ThemeService theme) {
    // 첫 번째 면 촬영 완료 후에는 두 번째 면 촬영 버튼 표시
    if (_captureStep == 1) {
      return AccessibleButton(
        label: '두 번째 면 촬영하기',
        icon: Icons.camera_alt,
        hint: '반대편 작은 면(두번째 면)을 촬영합니다',
        width: double.infinity,
        height: 70,
        onPressed: () => _captureSecondSide(theme),
      );
    }
    
    // 처음 시작할 때는 첫 번째 면 촬영 버튼
    return AccessibleButton(
      label: '촬영하기',
      icon: Icons.camera_alt,
      hint: '약 상자의 가장 좁은 면 양쪽을 모두 촬영합니다',
      width: double.infinity,
      height: 70,
      onPressed: () => _captureFirstSide(theme),
    );
  }

  Widget _buildBothResults(ThemeService theme) {
    return Semantics(
      container: true,
      label: "양쪽 면의 유통기한 인식 결과",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 첫 번째 면 결과
          _buildSideResult(
            theme: theme,
            sideNumber: 1,
            date: _firstExpiryDate,
            message: _firstMessage,
            status: _firstStatus,
          ),
          const SizedBox(height: 16),
          // 두 번째 면 결과
          _buildSideResult(
            theme: theme,
            sideNumber: 2,
            date: _secondExpiryDate,
            message: _secondMessage,
            status: _secondStatus,
          ),
          const SizedBox(height: 24),
          // 다시 촬영하기 버튼
          AccessibleButton(
            label: '다시 촬영하기',
            icon: Icons.camera_alt,
            hint: '양쪽 면을 다시 촬영합니다',
            width: double.infinity,
            height: 70,
            onPressed: () {
              setState(() {
                _firstImage = null;
                _secondImage = null;
                _firstExpiryDate = null;
                _firstMessage = null;
                _firstStatus = null;
                _secondExpiryDate = null;
                _secondMessage = null;
                _secondStatus = null;
                _errorMessage = null;
                _captureStep = 0;
              });
              if (theme.isVoiceGuideEnabled) {
                _tts.speak("다시 촬영할 수 있습니다. 위의 버튼을 눌러주세요.");
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSideResult({
    required ThemeService theme,
    required int sideNumber,
    DateTime? date,
    String? message,
    String? status,
  }) {
    final hasResult = date != null;
    final isNotFound = status == 'NOT_FOUND';
    final isExpired = message != null && (message.contains('지났') || message.contains('만료'));
    
    String labelText;
    if (hasResult) {
      final d = date!;
      labelText = "$sideNumber번째 면 결과. ${d.year}년 ${d.month}월 ${d.day}일. $message";
    } else if (isNotFound) {
      labelText = "$sideNumber번째 면 결과. 유통기한을 찾을 수 없었습니다";
    } else {
      labelText = "$sideNumber번째 면 결과. 결과 없음";
    }

    return Semantics(
      container: true,
      label: labelText,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: hasResult
              ? (isExpired 
                  ? Colors.red.withOpacity(0.1)
                  : theme.buttonColor)
              : theme.backgroundColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasResult
                ? (isExpired 
                    ? Colors.redAccent
                    : theme.primaryColor)
                : theme.textColor.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 면 번호와 상태
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$sideNumber',
                      style: theme.buttonTextStyle.copyWith(
                        fontSize: 20 * theme.fontScale,
                        fontWeight: FontWeight.bold,
                        color: theme.buttonTextColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$sideNumber번째 면',
                    style: theme.titleStyle.copyWith(
                      fontSize: 22 * theme.fontScale,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasResult)
                  Icon(
                    isExpired ? Icons.warning : Icons.check_circle,
                    color: isExpired ? Colors.redAccent : theme.primaryColor,
                    size: 28,
                  )
                else if (isNotFound)
                  Icon(
                    Icons.search_off,
                    color: theme.textColor.withOpacity(0.5),
                    size: 28,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (hasResult) ...[
              // 유통기한 날짜
              Semantics(
                header: true,
                label: "인식된 유통기한 날짜",
                child: Text(
                  '${date!.year}년 ${date!.month}월 ${date!.day}일',
                  style: theme.titleStyle.copyWith(
                    fontSize: 24 * theme.fontScale,
                    fontWeight: FontWeight.bold,
                    color: isExpired 
                        ? Colors.redAccent
                        : theme.textColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 상태 메시지
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isExpired 
                      ? Colors.redAccent.withOpacity(0.1)
                      : theme.backgroundColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message ?? '',
                  style: theme.bodyTextStyle.copyWith(
                    fontSize: 18 * theme.fontScale,
                    fontWeight: FontWeight.w600,
                    color: isExpired 
                        ? Colors.redAccent
                        : theme.textColor,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else if (isNotFound) ...[
              Text(
                '유통기한을 찾을 수 없었습니다',
                style: theme.bodyTextStyle.copyWith(
                  fontSize: 18 * theme.fontScale,
                  color: theme.textColor.withOpacity(0.7),
                ),
              ),
            ] else ...[
              Text(
                '결과 없음',
                style: theme.bodyTextStyle.copyWith(
                  fontSize: 18 * theme.fontScale,
                  color: theme.textColor.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeService theme) {
    return Semantics(
      container: true,
      label: "오류 발생. ${_errorMessage ?? '오류가 발생했습니다.'}",
      child: CustomErrorWidget(
        message: _errorMessage ?? '오류가 발생했습니다.',
        onRetry: () {
          setState(() {
            _errorMessage = null;
            _firstImage = null;
            _secondImage = null;
            _firstExpiryDate = null;
            _firstMessage = null;
            _firstStatus = null;
            _secondExpiryDate = null;
            _secondMessage = null;
            _secondStatus = null;
            _captureStep = 0;
          });
          if (theme.isVoiceGuideEnabled) {
            _tts.speak("다시 시도할 수 있습니다. 위의 버튼을 눌러주세요.");
          }
        },
      ),
    );
  }

  Widget _buildHelperText(ThemeService theme) {
    return Semantics(
      label: "촬영 안내. 약상자의 작은 면 부분에서 사용기한이나 EXP 텍스트가 보이는 부분을 약 30센티미터 떨어뜨려서 촬영하세요.",
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.backgroundColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.primaryColor,
                  size: 24 * theme.fontScale,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '촬영 안내',
                    style: theme.titleStyle.copyWith(
                      fontSize: 20 * theme.fontScale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '• 약상자의 작은 면 부분을 찾아주세요\n'
              '• "사용기한", "EXP", "유통기한" 텍스트를 인식합니다\n'
              '• 만약 결과가 나오지 않으면 다른 면으로 다시 촬영해주세요\n'
              '• 약 30센티미터 정도 떨어뜨려서 촬영하면 인식이 더 잘 됩니다\n'
              '• 너무 가까이 촬영하지 마세요',
              style: theme.bodyTextStyle.copyWith(
                fontSize: 18 * theme.fontScale,
                height: 1.6,
              ),
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

}