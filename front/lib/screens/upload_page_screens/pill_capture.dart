

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibration/vibration.dart';

import 'package:pillypilly_h/api_services/api_helper.dart';
import 'package:pillypilly_h/utils/app_colors.dart';
import 'package:pillypilly_h/utils/app_text_styles.dart';
import 'package:pillypilly_h/services/theme_service.dart';
import 'package:pillypilly_h/widgets/accessible_scaffold.dart';
import 'package:pillypilly_h/widgets/accessible_button.dart';
import 'package:provider/provider.dart';
import 'prescription_result.dart';
import 'pill_camera_preview.dart';

class PillCapturePage extends StatefulWidget {
  final String prescriptionId;
  final int totalCount;

  const PillCapturePage({
    Key? key,
    required this.prescriptionId,
    required this.totalCount,
  }) : super(key: key);

  @override
  State<PillCapturePage> createState() => _PillCapturePageState();
}

class _PillCapturePageState extends State<PillCapturePage> {
  final FlutterTts _tts = FlutterTts();
  final ImagePicker _picker = ImagePicker();
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  CancelToken? _cancelToken;

  String? _prescriptionId;
  int _totalCount = 1;
  int _currentIndex = 0;
  bool _initialized = false;

  bool _busy = false;
  double _progress = 0.0;

  final List<File> _capturedImages = [];
  final List<dynamic> _results = [];

  TextStyle _cap(BuildContext c) => AppTextStyles.body(c).copyWith(
        fontSize: 13,
        height: 1.3,
        color: AppColors.textPrimary(c).withOpacity(0.75),
      );

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _cancelToken?.cancel("dispose");
    _tts.stop();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;

    _prescriptionId = widget.prescriptionId;
    _totalCount = widget.totalCount;
    _initialized = true;

    _announce(
      "알약 촬영 화면입니다. "
      "반드시 한 개씩 찍고, 결과는 찍은 순서로 나오니까 유의해야 합니다. "
      "약을 1번부터 $_totalCount번까지 순서대로 세로 방향으로 촬영하거나 갤러리에서 선택해주세요. "
      "현재 1번 약을 촬영할 차례입니다.",
    );
  }

  Future<void> _announce(String text, {bool interrupt = true}) async {
    try {
      final theme = context.read<ThemeService>();
      if (!theme.isVoiceGuideEnabled) return;
      
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.47);
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _vibrate({int duration = 120}) async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
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

  /// ③ 알약 인식 → /api/v3/image-search
  Future<Response> _postImage({
    required File fileToSend,
    required int orderIndex,
  }) async {
    _cancelToken?.cancel("restart");
    _cancelToken = CancelToken();

    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    final url = '${_cleanBase(baseUrl)}/api/v3/image-search';

    final filename = fileToSend.path.split('/').last;

    final formData = FormData.fromMap({
      'file': MultipartFile.fromFileSync(fileToSend.path, filename: filename),
      'prescription_id': _prescriptionId,
      'order_index': orderIndex,
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
        final uploadP = (sent / totalBytes).clamp(0.0, 1.0);
        setState(() => _progress = uploadP);
      },
    );
  }

  /// 카메라 촬영 (YOLO 프리뷰 화면으로 이동)
  Future<void> _openCameraPreview() async {
    if (_busy) return;
    if (_currentIndex >= _totalCount) {
      _showSnack("이미 모든 알약을 촬영했습니다.");
      return;
    }

    if (_prescriptionId == null || _prescriptionId!.trim().isEmpty) {
      _showSnack("처방전 세션 정보가 없습니다. 이전 단계에서 다시 시도해주세요.",
          color: Colors.redAccent);
      await _announce("처방전 세션 정보가 없습니다. 이전 단계로 돌아가 다시 시도해주세요.");
      return;
    }

    // YOLO 프리뷰 화면으로 이동
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PillCameraPreviewPage(
          prescriptionId: _prescriptionId!,
          currentIndex: _currentIndex,
          totalCount: _totalCount,
          onImageCaptured: (file) {
            // 이미지 파일을 받아서 업로드
            _uploadImageFile(file);
          },
        ),
      ),
    );
  }

  /// 이미지 파일 업로드
  Future<void> _uploadImageFile(File file) async {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    if (baseUrl.isEmpty) {
      _showSnack(".env의 API_BASE_URL이 설정되지 않았습니다.", color: Colors.redAccent);
      await _announce("서버 주소가 설정되지 않았습니다.");
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0.0;
    });

    try {
      if (_capturedImages.length <= _currentIndex) {
        _capturedImages.add(file);
      } else {
        _capturedImages[_currentIndex] = file;
      }

      await _announce(
        "${_currentIndex + 1}번 약 이미지를 서버로 전송합니다.",
      );

      final res = await _postImage(
        fileToSend: file,
        orderIndex: _currentIndex,
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        // 서버 응답에 인식 결과 리스트가 있을 수도 있으므로 안전하게 처리
        if (res.data is Map && (res.data['results'] is List)) {
          final list = (res.data['results'] as List).cast<dynamic>();
          if (_results.length <= _currentIndex) {
            _results.add(list);
          } else {
            _results[_currentIndex] = list;
          }
        }

        setState(() {
          _currentIndex += 1;
          _progress = 1.0;
          _busy = false;
        });

        await _vibrate(duration: 160);

        if (_currentIndex < _totalCount) {
          final nextMsg = "${_currentIndex}개 촬영이 완료되었습니다. 다음 ${_currentIndex + 1}번 약을 촬영해주세요.";
          await _announce(nextMsg);
          // Talkback을 위한 Semantics 업데이트
          SemanticsService.announce(
            "총 $_totalCount개 중 ${_currentIndex + 1}번 알약을 촬영합니다. $nextMsg",
            TextDirection.ltr,
          );
        } else {
          final completeMsg = "모든 알약 촬영이 완료되었습니다. 서버에서 인식과 분석을 진행합니다.";
          await _announce(completeMsg);
          SemanticsService.announce(completeMsg, TextDirection.ltr);
          _showSnack("모든 알약 촬영 완료!");
        }
      } else {
        final msg = () {
          final d = res.data;
          if (d is Map && d['message'] != null) return d['message'].toString();
          if (d is Map && d['error'] != null) return d['error'].toString();
          return d?.toString();
        }();

        setState(() {
          _busy = false;
        });

        _showSnack(
          "업로드 실패: ${res.statusCode} $msg",
          color: Colors.redAccent,
        );
        await _announce("알약 이미지 업로드에 실패했습니다. 다시 시도해주세요.");
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final responseData = e.response?.data;
      String pretty = "네트워크 또는 서버 오류";

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        pretty = "네트워크 시간 초과";
      } else if (e.type == DioExceptionType.cancel) {
        pretty = "요청이 취소되었습니다.";
      } else if (code == 502) {
        // 502 Bad Gateway: 외부 API 호출 실패
        final errorMsg = responseData is Map 
            ? (responseData['error']?['message'] ?? responseData['message'] ?? '외부 서비스 연결 실패')
            : '서버가 외부 서비스에 연결할 수 없습니다';
        pretty = "서버 연결 오류: $errorMsg";
      } else if (code == 500) {
        pretty = "서버 내부 오류가 발생했습니다";
      } else if (code == 503) {
        pretty = "서버가 일시적으로 사용할 수 없습니다";
      } else if (code != null) {
        pretty = "서버 오류($code)";
      }

      setState(() {
        _busy = false;
      });

      _showSnack(pretty, color: Colors.redAccent);
      await _announce("알약 이미지 업로드에 실패했습니다. $pretty");
    } catch (e) {
      setState(() {
        _busy = false;
      });
      _showSnack("알 수 없는 오류: ${e.toString()}", color: Colors.redAccent);
      await _announce("알약 이미지 업로드 중 알 수 없는 오류가 발생했습니다.");
    }
  }

  /// 갤러리에서 이미지 선택 및 업로드
  Future<void> _selectAndUploadImage(ImageSource source) async {
    if (_busy) return;
    if (_currentIndex >= _totalCount) {
      _showSnack("이미 모든 알약을 촬영했습니다.");
      return;
    }

    final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
    if (baseUrl.isEmpty) {
      _showSnack(".env의 API_BASE_URL이 설정되지 않았습니다.", color: Colors.redAccent);
      await _announce("서버 주소가 설정되지 않았습니다.");
      return;
    }

    if (_prescriptionId == null || _prescriptionId!.trim().isEmpty) {
      _showSnack("처방전 세션 정보가 없습니다. 이전 단계에서 다시 시도해주세요.",
          color: Colors.redAccent);
      await _announce("처방전 세션 정보가 없습니다. 이전 단계로 돌아가 다시 시도해주세요.");
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0.0;
    });

    try {
      // 이미지 선택 (카메라 또는 갤러리)
      final XFile? picked;
      if (source == ImageSource.camera) {
        picked = await _picker.pickImage(
          source: source,
          imageQuality: 95,
          preferredCameraDevice: CameraDevice.rear,
        );
      } else {
        picked = await _picker.pickImage(
          source: source,
          imageQuality: 95,
        );
      }

      if (!mounted) return;

      if (picked == null) {
        final cancelMsg = source == ImageSource.camera 
            ? "촬영이 취소되었습니다." 
            : "이미지 선택이 취소되었습니다.";
        _showSnack(cancelMsg);
        await _announce(cancelMsg);
        setState(() => _busy = false);
        return;
      }

      final file = File(picked.path);
      if (_capturedImages.length <= _currentIndex) {
        _capturedImages.add(file);
      } else {
        _capturedImages[_currentIndex] = file;
      }

      await _announce(
        "${_currentIndex + 1}번 약 이미지를 서버로 전송합니다.",
      );

      final res = await _postImage(
        fileToSend: file,
        orderIndex: _currentIndex,
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        // 서버 응답에 인식 결과 리스트가 있을 수도 있으므로 안전하게 처리
        if (res.data is Map && (res.data['results'] is List)) {
          final list = (res.data['results'] as List).cast<dynamic>();
          if (_results.length <= _currentIndex) {
            _results.add(list);
          } else {
            _results[_currentIndex] = list;
          }
        }

        setState(() {
          _currentIndex += 1;
          _progress = 1.0;
          _busy = false;
        });

        await _vibrate(duration: 160);

        if (_currentIndex < _totalCount) {
          final nextMsg = "${_currentIndex}개 촬영이 완료되었습니다. 다음 ${_currentIndex + 1}번 약을 촬영해주세요.";
          await _announce(nextMsg);
          // Talkback을 위한 Semantics 업데이트
          SemanticsService.announce(
            "총 $_totalCount개 중 ${_currentIndex + 1}번 알약을 촬영합니다. $nextMsg",
            TextDirection.ltr,
          );
        } else {
          final completeMsg = "모든 알약 촬영이 완료되었습니다. 서버에서 인식과 분석을 진행합니다.";
          await _announce(completeMsg);
          SemanticsService.announce(completeMsg, TextDirection.ltr);
          _showSnack("모든 알약 촬영 완료!");
        }
      } else {
        final msg = () {
          final d = res.data;
          if (d is Map && d['message'] != null) return d['message'].toString();
          if (d is Map && d['error'] != null) return d['error'].toString();
          return d?.toString();
        }();

        setState(() {
          _busy = false;
        });

        _showSnack(
          "업로드 실패: ${res.statusCode} $msg",
          color: Colors.redAccent,
        );
        await _announce("알약 이미지 업로드에 실패했습니다. 다시 시도해주세요.");
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final responseData = e.response?.data;
      String pretty = "네트워크 또는 서버 오류";

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        pretty = "네트워크 시간 초과";
      } else if (e.type == DioExceptionType.cancel) {
        pretty = "요청이 취소되었습니다.";
      } else if (code == 502) {
        // 502 Bad Gateway: 외부 API 호출 실패
        final errorMsg = responseData is Map 
            ? (responseData['error']?['message'] ?? responseData['message'] ?? '외부 서비스 연결 실패')
            : '서버가 외부 서비스에 연결할 수 없습니다';
        pretty = "서버 연결 오류: $errorMsg";
      } else if (code == 500) {
        pretty = "서버 내부 오류가 발생했습니다";
      } else if (code == 503) {
        pretty = "서버가 일시적으로 사용할 수 없습니다";
      } else if (code != null) {
        pretty = "서버 오류($code)";
      }

      setState(() {
        _busy = false;
      });

      _showSnack(pretty, color: Colors.redAccent);
      await _announce("알약 이미지 업로드에 실패했습니다. $pretty");
    } catch (e) {
      setState(() {
        _busy = false;
      });
      _showSnack("알 수 없는 오류: ${e.toString()}", color: Colors.redAccent);
      await _announce("알약 이미지 업로드 중 알 수 없는 오류가 발생했습니다.");
    }
  }

  void _onFinish() {
    _announce(
      "모든 알약 촬영이 완료되었습니다. 최종 결과 화면으로 이동합니다.",
    );

    if (_prescriptionId == null || _prescriptionId!.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PrescriptionResultPage(
          prescriptionId: _prescriptionId!.trim(),
          totalCount: _totalCount,
          pillsCaptured: true, // 알약 촬영 완료 표시
        ),
      ),
    );
  }

  void _onBackToSetup() {
    _announce("이전 단계로 돌아갑니다.");
    Navigator.pop(context);
  }

  Future<void> _deleteImage(int index) async {
    if (index < 0 || index >= _capturedImages.length) return;
    
    await _announce("${index + 1}번 알약 이미지를 삭제합니다.");
    
    setState(() {
      _capturedImages.removeAt(index);
      if (index < _results.length) {
        _results.removeAt(index);
      }
      // 삭제된 이미지가 현재 인덱스보다 앞이면 현재 인덱스 조정
      if (index < _currentIndex) {
        _currentIndex--;
      }
      // 현재 인덱스가 범위를 벗어나면 조정
      if (_currentIndex > _capturedImages.length) {
        _currentIndex = _capturedImages.length;
      }
    });
    
    await _vibrate(duration: 100);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (_totalCount - _currentIndex).clamp(0, _totalCount);
    final isCompleted = _currentIndex >= _totalCount;

    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: "알약 촬영",
          body: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          container: true,
          label: isCompleted
              ? "모든 알약 촬영이 완료되었습니다."
              : "알약 촬영 화면. 총 $_totalCount개 중 ${_currentIndex + 1}번 알약을 촬영합니다.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                label: isCompleted
                    ? "모든 알약 촬영이 완료되었습니다."
                    : "총 $_totalCount개 중 ${_currentIndex + 1}번 알약을 촬영합니다.",
                child: Text(
                  isCompleted
                      ? "모든 알약 촬영이 완료되었습니다."
                      : "총 $_totalCount개 중 ${_currentIndex + 1}번 알약을 촬영합니다.",
                  style: AppTextStyles.title(context),
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: isCompleted
                    ? "이제 결과 분석이 완료되면 처방전 결과 화면에서 확인하실 수 있습니다."
                    : "약을 세로 방향으로 화면 중앙에 오게 맞춘 뒤, 촬영 버튼을 눌러주세요.",
                child: Text(
                  isCompleted
                      ? "이제 결과 분석이 완료되면 처방전 결과 화면에서 확인하실 수 있습니다."
                      : "약을 세로 방향으로 화면 중앙에 오게 맞춘 뒤, 촬영 버튼을 눌러주세요.",
                  style: _cap(context),
                ),
              ),
              const SizedBox(height: 16),

              if (!_busy && !isCompleted) ...[
                AccessibleButton(
                  label: "촬영하기",
                  icon: Icons.camera_alt,
                  hint: "총 $_totalCount개 중 ${_currentIndex + 1}번 알약을 촬영합니다. 카메라 화면으로 이동합니다.",
                  onPressed: _openCameraPreview,
                  height: 56,
                ),
                const SizedBox(height: 12),
                AccessibleButton(
                  label: "갤러리에서 선택",
                  icon: Icons.photo_library,
                  hint: "총 $_totalCount개 중 ${_currentIndex + 1}번 알약 이미지를 갤러리에서 선택합니다.",
                  onPressed: () => _selectAndUploadImage(ImageSource.gallery),
                  height: 56,
                  backgroundColor: theme.buttonColor.withOpacity(0.8),
                ),
              ],

              if (_busy) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  label: "업로드 진행률",
                  value:
                      "${(_progress * 100).clamp(0, 100).toStringAsFixed(0)} 퍼센트",
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LinearProgressIndicator(
                        value: _progress,
                        color: theme.primaryColor,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "이미지를 서버로 전송 중입니다...",
                        style: _cap(context),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // 이미 촬영된 썸네일 리스트
              if (_capturedImages.isNotEmpty)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "촬영된 알약 (${_capturedImages.length} / $_totalCount)",
                        style: _cap(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _capturedImages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final file = _capturedImages[index];
                            return Semantics(
                              button: true,
                              label: "${index + 1}번 알약 이미지",
                              hint: "이미지를 삭제하려면 삭제 버튼을 누르세요",
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: 90,
                                        height: 90,
                                        decoration: BoxDecoration(
                                          color: AppColors.card(context),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: index == _currentIndex - 1
                                                ? theme.primaryColor
                                                : Colors.grey.shade400,
                                            width: 2,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Image.file(
                                          file,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        top: -8,
                                        right: -8,
                                        child: Semantics(
                                          button: true,
                                          label: "${index + 1}번 알약 이미지 삭제",
                                          hint: "이 이미지를 삭제합니다",
                                          child: Material(
                                            color: Colors.red,
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              onTap: () => _deleteImage(index),
                                              borderRadius: BorderRadius.circular(12),
                                              child: Container(
                                                width: 24,
                                                height: 24,
                                                decoration: const BoxDecoration(
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${index + 1}번",
                                    style: _cap(context).copyWith(fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: Center(
                    child: Text(
                      "아직 촬영된 알약이 없습니다.",
                      style: _cap(context),
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // 하단 버튼들
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _onBackToSetup,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text("이전 단계"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          (_busy || !isCompleted) ? null : _onFinish,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: theme.buttonColor,
                        foregroundColor: theme.buttonTextColor,
                      ),
                      child: Text(
                        isCompleted ? "결과 보기" : "촬영 진행 중",
                      ),
                    ),
                  ),
                ],
              ),
              if (!isCompleted)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    "남은 알약: $remaining개",
                    textAlign: TextAlign.right,
                    style: _cap(context).copyWith(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
        );
      },
    );
  }
}