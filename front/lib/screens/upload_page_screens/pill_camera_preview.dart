import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';

class PillCameraPreviewPage extends StatefulWidget {
  final String prescriptionId;
  final int currentIndex;
  final int totalCount;
  final Function(File imageFile) onImageCaptured;

  const PillCameraPreviewPage({
    Key? key,
    required this.prescriptionId,
    required this.currentIndex,
    required this.totalCount,
    required this.onImageCaptured,
  }) : super(key: key);

  @override
  State<PillCameraPreviewPage> createState() => _PillCameraPreviewPageState();
}

class _PillCameraPreviewPageState extends State<PillCameraPreviewPage> {
  final FlutterTts _tts = FlutterTts();
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  
  bool _isInitialized = false;
  bool _isCapturing = false;

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

  Future<void> _announce(String text, {bool interrupt = false}) async {
    final theme = context.read<ThemeService>();
    if (theme.isVoiceGuideEnabled) {
      await _tts.setLanguage("ko-KR");
      await _tts.setSpeechRate(0.5);
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    }
    SemanticsService.announce(text, TextDirection.ltr);
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
        await _announce(
          "알약 촬영 화면입니다. "
          "총 ${widget.totalCount}개 중 ${widget.currentIndex + 1}번 알약을 촬영합니다. "
          "반드시 한 개씩 찍고, 결과는 찍은 순서로 나오니까 유의해야 합니다. "
          "알약을 화면 중앙에 비춰주세요. 하나씩 촬영해주세요.",
        );
      }
    } catch (e) {
      debugPrint("카메라 초기화 오류: $e");
      await _announce("카메라 초기화 중 오류가 발생했습니다.");
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  /// 이미지 캡처 및 콜백 호출
  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    debugPrint('📸 [알약 촬영] 촬영 버튼 클릭됨');
    final theme = context.read<ThemeService>();

    setState(() {
      _isCapturing = true;
    });

    try {
      debugPrint('📸 [알약 촬영] 촬영 시작...');
      if (theme.isVoiceGuideEnabled) {
        await _announce("촬영 중입니다. 잠시만 기다려주세요.");
      }

      final image = await _controller!.takePicture();
      debugPrint('✅ [알약 촬영] 촬영 완료: ${image.path}');
      
      await Vibration.vibrate(duration: 200);

      if (theme.isVoiceGuideEnabled) {
        await _announce("${widget.currentIndex + 1}번 알약 촬영이 완료되었습니다.");
      }

      // Talkback을 위한 Semantics 업데이트
      SemanticsService.announce(
        "${widget.currentIndex + 1}번 알약 촬영 완료",
        TextDirection.ltr,
      );

      debugPrint('📸 [알약 촬영] 콜백 호출 전...');
      // 콜백으로 이미지 파일 전달
      widget.onImageCaptured(File(image.path));
      debugPrint('✅ [알약 촬영] 콜백 호출 완료');
      
      if (mounted) {
        debugPrint('📸 [알약 촬영] 화면 닫기');
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      debugPrint("❌ [알약 촬영] 촬영 오류: $e");
      debugPrint("❌ [알약 촬영] 스택 트레이스: $stackTrace");
      if (theme.isVoiceGuideEnabled) {
        await _announce("촬영 중 오류가 발생했습니다.");
      }
      SemanticsService.announce(
        "촬영 중 오류가 발생했습니다.",
        TextDirection.ltr,
      );
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
    if (!_isInitialized) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        final statusText = "총 ${widget.totalCount}개 중 ${widget.currentIndex + 1}번 알약 촬영";

        return AccessibleScaffold(
          title: statusText,
          backgroundColor: Colors.black,
          body: Semantics(
            label: "$statusText. 알약을 화면 중앙에 비춰주세요. 하나씩 촬영해주세요. 촬영하기 버튼을 눌러 현재 화면의 알약을 촬영할 수 있습니다.",
            child: Stack(
              children: [
                // 카메라 프리뷰
                Positioned.fill(
                  child: Semantics(
                    label: "카메라 프리뷰. 알약을 화면 중앙에 비춰주세요.",
                    child: CameraPreview(_controller!),
                  ),
                ),
                
                // 상단 상태 표시
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Semantics(
                    liveRegion: true,
                    label: statusText,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: Colors.black.withOpacity(0.7),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18 * theme.fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                
                // 하단 안내 및 촬영 버튼
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.9),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 안내 문구
                        Semantics(
                          liveRegion: true,
                          label: "알약을 화면 중앙에 비춰주세요. 하나씩 촬영해주세요",
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "알약을 화면 중앙에 비춰주세요",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18 * theme.fontScale,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "하나씩 촬영해주세요",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14 * theme.fontScale,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        
                        // 촬영 버튼
                        Semantics(
                          button: true,
                          label: "촬영하기",
                          hint: "현재 화면의 알약을 촬영합니다. 알약을 화면 중앙에 비춰주세요.",
                          child: ElevatedButton.icon(
                            onPressed: _isCapturing ? null : _captureImage,
                            icon: Icon(Icons.camera_alt, size: 32),
                            label: Text(
                              "촬영하기",
                              style: TextStyle(
                                fontSize: 22 * theme.fontScale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, 70),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
