import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';

// ✅ ultralytics_yolo import
import 'package:ultralytics_yolo/yolo_view.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/models/yolo_task.dart';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';

class PillCameraScreen extends StatefulWidget {
  const PillCameraScreen({super.key});

  @override
  State<PillCameraScreen> createState() => _PillCameraScreenState();
}

class _PillCameraScreenState extends State<PillCameraScreen> {
  final FlutterTts tts = FlutterTts();
  final Dio dio = Dio();

  late YOLOViewController _controller;
  List<YOLOResult> _results = [];
  int _pillCount = 0;

  bool _isInitialized = false;
  bool _isSpeaking = false;

  Uint8List? _lastFrameBytes;

  // YOLO 기본 설정값
  static const double _confTh = 0.25;
  static const double _iouTh = 0.45;
  static const bool _useGpu = false; // 우선 CPU로 안정화 후 필요 시 true로 변경

  // ✅ 0.1.38 버전에서 지원되는 YOLOStreamingConfig
  final YOLOStreamingConfig _streaming = const YOLOStreamingConfig();

  @override
  void initState() {
    super.initState();
    _controller = YOLOViewController();
    _init();
  }

  Future<void> _init() async {
    await tts.speak("카메라와 모델을 준비합니다. 알약을 비춰주세요.");
    setState(() => _isInitialized = true);
  }

  // 실시간 감지 콜백
  void _onResult(List<YOLOResult> results) async {
    print('[YOLO] detections=${results.length}');
    for (final r in results.take(3)) {
      print('[YOLO] class=${r.className} conf=${r.confidence.toStringAsFixed(3)} box=${r.boundingBox}');
    }

    final pillCount = results.length;
    if (pillCount != _pillCount && !_isSpeaking) {
      _pillCount = pillCount;
      _results = results;
      _isSpeaking = true;

      await tts.speak("현재 $_pillCount개의 알약이 감지되었습니다.");
      Vibration.vibrate(duration: 60);

      _isSpeaking = false;
      if (mounted) setState(() {});
    }
  }

  // 스트리밍 데이터 콜백
  void _onStreamingData(Map<String, dynamic> data) {
    try {
      final dynamic anyBytes =
          data['imageBytes'] ?? data['jpegBytes'] ?? data['pngBytes'] ?? data['annotatedImage'];
      if (anyBytes is Uint8List) {
        _lastFrameBytes = anyBytes;
      } else if (anyBytes is List<int>) {
        _lastFrameBytes = Uint8List.fromList(anyBytes);
      }
      print('[YOLO] streaming keys: ${data.keys.join(', ')}');
    } catch (_) {}
  }

  // 프레임 저장 후 서버 업로드
  Future<void> _captureImage() async {
    try {
      if (_lastFrameBytes == null) {
        await tts.speak("아직 이미지 프레임을 받지 못했습니다. 잠시 후 다시 시도해주세요.");
        return;
      }

      final tmpDir = await Directory.systemTemp.createTemp('pillcap_');
      final path = '${tmpDir.path}/pill_frame.jpg';
      final file = File(path);
      await file.writeAsBytes(_lastFrameBytes!);

      await tts.speak("촬영이 완료되었습니다. $_pillCount 개의 알약이 맞나요?");
      _showConfirmDialog(file);
    } catch (e) {
      debugPrint("프레임 저장 오류: $e");
      await tts.speak("촬영 중 오류가 발생했습니다.");
    }
  }

  void _showConfirmDialog(File imageFile) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black,
        title: Text(
          "$_pillCount개의 알약이 맞습니까?",
          style: const TextStyle(color: Colors.yellow),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadToServer(imageFile);
            },
            child: const Text("예", style: TextStyle(color: Colors.yellow)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              tts.speak("다시 촬영해주세요.");
            },
            child: const Text("아니오", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadToServer(File imageFile) async {
    await tts.speak("서버로 이미지를 전송합니다.");
    try {
      final res = await dio.post(
        "https://your-server.com/api/pill-detect",
        data: FormData.fromMap({
          "image": await MultipartFile.fromFile(imageFile.path),
          "pillCount": _pillCount,
        }),
      );
      final result = res.data["result"] ?? "결과를 불러올 수 없습니다.";
      await tts.speak("결과는 $result 입니다.");
    } catch (e) {
      debugPrint("업로드 오류: $e");
      await tts.speak("전송에 실패했습니다.");
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.yellow,
        title: const Text("YOLOv8 실시간 알약 감지"),
      ),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.yellow))
          : Stack(
              fit: StackFit.expand,
              children: [
                YOLOView(
                  modelPath: 'assets/models/best_detect_0715_float16.tflite',
                  task: YOLOTask.detect,
                  controller: _controller,

                  cameraResolution: '480p',
                  useGpu: _useGpu,
                  confidenceThreshold: _confTh,
                  iouThreshold: _iouTh,
                  streamingConfig: _streaming,

                  onResult: _onResult,
                  onStreamingData: _onStreamingData,
                ),

                // 상단 디버그 텍스트
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    child: Text(
                      'detected: $_pillCount  |  GPU:${_useGpu}  |  conf>=${_confTh.toStringAsFixed(2)}  IoU=${_iouTh.toStringAsFixed(2)}  |  res=480p',
                      style: const TextStyle(color: Colors.yellow, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                if (_pillCount > 0)
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        '감지된 알약: $_pillCount개',
                        style: const TextStyle(
                          color: Colors.yellow,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.yellow,
        onPressed: _captureImage,
        child: const Icon(Icons.camera_alt, color: Colors.black),
      ),
    );
  }
}