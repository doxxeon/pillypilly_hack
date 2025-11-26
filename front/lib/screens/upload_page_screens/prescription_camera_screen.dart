import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';

/// 처방전 촬영용 카메라 화면
class PrescriptionCameraScreen extends StatefulWidget {
  const PrescriptionCameraScreen({Key? key}) : super(key: key);

  @override
  State<PrescriptionCameraScreen> createState() => _PrescriptionCameraScreenState();
}

class _PrescriptionCameraScreenState extends State<PrescriptionCameraScreen> {
  CameraController? _controller;
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isCapturing = false;
  List<CameraDescription>? _cameras;
  FlashMode _flashMode = FlashMode.auto;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        await _announce("카메라를 사용할 수 없습니다.");
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // 후면 카메라 사용
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.max, // 최대 해상도 사용 (3024x4032 등)
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        await _announce("처방전 촬영 화면입니다. 처방전을 세로로 길게 화면에 맞춰주세요. 만약 결과가 나오지 않는다면 처방전을 180도로 돌려서 다시 한 번 촬영해주세요.");
      }
    } catch (e) {
      debugPrint("카메라 초기화 오류: $e");
      await _announce("카메라 초기화 중 오류가 발생했습니다.");
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _announce(String text) async {
    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
      // Talkback을 위한 Semantics 업데이트 (음성안내가 켜져 있을 때만)
      SemanticsService.announce(text, TextDirection.ltr);
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      FlashMode newMode;
      String announcement;
      
      switch (_flashMode) {
        case FlashMode.auto:
          newMode = FlashMode.always;
          announcement = "플래시가 켜졌습니다";
          break;
        case FlashMode.always:
          newMode = FlashMode.off;
          announcement = "플래시가 꺼졌습니다";
          break;
        case FlashMode.off:
          newMode = FlashMode.auto;
          announcement = "플래시가 자동 모드로 설정되었습니다";
          break;
        default:
          newMode = FlashMode.auto;
          announcement = "플래시가 자동 모드로 설정되었습니다";
      }

      await _controller!.setFlashMode(newMode);
      
      if (mounted) {
        setState(() {
          _flashMode = newMode;
        });
        await _announce(announcement);
      }
    } catch (e) {
      debugPrint("플래시 토글 오류: $e");
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      await _announce("촬영 중입니다. 잠시만 기다려주세요.");
      
      final image = await _controller!.takePicture();
      await Vibration.vibrate(duration: 200);
      
      await _announce("촬영이 완료되었습니다.");
      
      if (mounted) {
        Navigator.pop(context, File(image.path));
      }
    } catch (e) {
      debugPrint("촬영 오류: $e");
      await _announce("촬영 중 오류가 발생했습니다.");
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: "처방전 촬영",
          backgroundColor: Colors.black,
          body: !_isInitialized
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Stack(
                  children: [
                    // 카메라 프리뷰 (전체 화면)
                    Positioned.fill(
                      child: CameraPreview(_controller!),
                    ),
                    
                    // 상단 안내
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Semantics(
                          label: "처방전을 세로로 길게 화면에 맞춰주세요. 만약 결과가 나오지 않는다면 처방전을 180도로 돌려서 다시 한 번 촬영해주세요.",
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "처방전을 세로로 길게 화면에 맞춰주세요",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18 * theme.fontScale,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "만약 결과가 나오지 않는다면 처방전을 180도로 돌려서 다시 한 번 촬영해주세요",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16 * theme.fontScale,
                                  fontWeight: FontWeight.normal,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    
                    // 우측 상단 플래시 버튼
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Semantics(
                        button: true,
                        label: _flashMode == FlashMode.auto
                            ? "플래시 자동 모드. 탭하여 켜기로 변경"
                            : _flashMode == FlashMode.always
                                ? "플래시 켜짐. 탭하여 끄기로 변경"
                                : "플래시 꺼짐. 탭하여 자동 모드로 변경",
                        hint: "플래시 모드를 변경합니다",
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _toggleFlash,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _flashMode == FlashMode.auto
                                    ? Icons.flash_auto
                                    : _flashMode == FlashMode.always
                                        ? Icons.flash_on
                                        : Icons.flash_off,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    // 하단 촬영 버튼
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.9),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Semantics(
                          button: true,
                          label: "촬영하기",
                          hint: "처방전을 촬영합니다",
                          child: ElevatedButton.icon(
                            onPressed: _isCapturing ? null : _captureImage,
                            icon: Icon(
                              Icons.camera_alt,
                              size: 32,
                            ),
                            label: Text(
                              _isCapturing ? "촬영 중..." : "촬영하기",
                              style: TextStyle(
                                fontSize: 22 * theme.fontScale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 70),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

