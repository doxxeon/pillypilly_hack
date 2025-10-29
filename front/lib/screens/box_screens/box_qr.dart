// lib/screens/box_screens/box_qr.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:pillypilly_h/api_services/api_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class BoxQrScreen extends StatefulWidget {
  const BoxQrScreen({super.key});

  @override
  State<BoxQrScreen> createState() => _BoxQrScreenState();
}

class _BoxQrScreenState extends State<BoxQrScreen> {
  CameraController? _cam;
  bool _ready = false;
  bool _busy = false;
  bool _loading = false;

  final FlutterTts _tts = FlutterTts();
  late final BarcodeScanner _scanner;

  // 디버깅 상태
  int _frameCount = 0;
  int _consecutiveEmpty = 0;
  int _lastLogAt = 0;

  @override
  void initState() {
    super.initState();
    // 포맷 **전부** 허용: 필터 미지정
    _scanner = BarcodeScanner();
    _init();
  }

  Future<void> _init() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.45);
    await _tts.speak("카메라가 켜졌습니다. 상자 표면의 QR 또는 바코드를 중앙 박스에 맞춰 천천히 돌려가며 비춰주세요. 화면을 길게 누르면 사진으로도 시도합니다.");

    final cams = await availableCameras();
    final back = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    _cam = CameraController(
      back,
      ResolutionPreset.high, // high가 인식률 좋음
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cam!.initialize();
    await _cam!.setFlashMode(FlashMode.auto);

    debugPrint("📷 Camera: ${back.name}  orientation=${back.sensorOrientation}");
    setState(() => _ready = true);
    _startStream();
  }

  double _avgLuma(CameraImage img) {
    // Y plane 평균 밝기
    final y = img.planes[0].bytes;
    int sum = 0;
    for (int i = 0; i < y.length; i += 50) {
      sum += y[i];
    }
    final sampleCount = (y.length / 50).ceil();
    return sampleCount == 0 ? 0 : sum / sampleCount / 255.0;
  }

  double _centerRoiLuma(CameraImage img) {
    // 중앙 25% 정사각(대략) 루마 평균
    final w = img.width;
    final h = img.height;
    final yPlane = img.planes[0];
    final bytes = yPlane.bytes;
    final stride = yPlane.bytesPerRow;

    final rw = (w * 0.5).round();
    final rh = (h * 0.5).round();
    final x0 = (w - rw) ~/ 2;
    final y0 = (h - rh) ~/ 2;

    int sum = 0, cnt = 0;
    for (int yy = y0; yy < y0 + rh; yy += 4) {
      final rowOff = yy * stride;
      for (int xx = x0; xx < x0 + rw; xx += 4) {
        sum += bytes[rowOff + xx];
        cnt++;
      }
    }
    return cnt == 0 ? 0 : (sum / cnt) / 255.0;
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    // 안전한 YUV420 → NV21
    final int w = image.width;
    final int h = image.height;
    final int ySize = w * h;
    final int uvSize = w * h ~/ 2;
    final out = Uint8List(ySize + uvSize);

    // Y
    out.setRange(0, ySize, image.planes[0].bytes);

    // UV interleave (VU)
    final u = image.planes[1];
    final v = image.planes[2];
    final uRowStride = u.bytesPerRow;
    final vRowStride = v.bytesPerRow;
    final uPixStride = u.bytesPerPixel ?? 1;
    final vPixStride = v.bytesPerPixel ?? 1;

    int uvIndex = ySize;
    for (int y = 0; y < h ~/ 2; y++) {
      for (int x = 0; x < w ~/ 2; x++) {
        final vIdx = y * vRowStride + x * vPixStride;
        final uIdx = y * uRowStride + x * uPixStride;
        out[uvIndex++] = v.bytes[vIdx];
        out[uvIndex++] = u.bytes[uIdx];
      }
    }
    return out;
  }

  void _startStream() {
    _cam!.startImageStream((CameraImage image) async {
      if (!mounted || _busy) return;
      _busy = true;

      final sw = Stopwatch()..start();
      try {
        _frameCount++;
        final luma = _avgLuma(image);
        final centerLuma = _centerRoiLuma(image);

        // 매 30프레임마다 자세한 파라미터 로그
        if (_frameCount - _lastLogAt >= 30) {
          _lastLogAt = _frameCount;
          final p0 = image.planes[0];
          final p1 = image.planes.length > 1 ? image.planes[1] : null;
          final p2 = image.planes.length > 2 ? image.planes[2] : null;

          debugPrint("🧪 FrameParams w=${image.width} h=${image.height} "
              "rot=${_cam!.description.sensorOrientation} "
              "Y{row=${p0.bytesPerRow},len=${p0.bytes.length}} "
              "U{row=${p1?.bytesPerRow},pix=${p1?.bytesPerPixel},len=${p1?.bytes.length}} "
              "V{row=${p2?.bytesPerRow},pix=${p2?.bytesPerPixel},len=${p2?.bytes.length}} "
              "avgLuma=${luma.toStringAsFixed(3)} centerLuma=${centerLuma.toStringAsFixed(3)}");
        }

        final bytes = _yuv420ToNv21(image);

        final input = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotationValue.fromRawValue(
                  _cam!.description.sensorOrientation,
                ) ??
                InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );

        final codes = await _scanner.processImage(input);

        debugPrint("📸 Frame: ${image.width}x${image.height}");
        debugPrint("⏱️ Frame 처리 시간: ${sw.elapsedMilliseconds}ms");
        debugPrint("📸 탐지된 바코드 개수: ${codes.length}");

        if (codes.isEmpty) {
          _consecutiveEmpty++;
          if (_consecutiveEmpty == 20) {
            debugPrint("⚠️ 20프레임 연속 미검출. 밝기=${luma.toStringAsFixed(2)}, 중앙=${centerLuma.toStringAsFixed(2)}."
                " 너무 어둡거나, 코드 포맷(예: Datamatrix/Code128)일 수 있음. 플래시를 켜보세요.");
          }
        } else {
          _consecutiveEmpty = 0;
          // 가장 신뢰도 높은 첫 코드
          final b = codes.first;
          final raw = b.rawValue ?? "";
          debugPrint("✅ 감지됨: format=${b.format} value=$raw box=${b.boundingBox}");

          if (raw.isNotEmpty) {
            await _cam?.stopImageStream();
            await _onRecognized(raw);
          }
        }
      } catch (e, st) {
        debugPrint("❌ 디코딩 오류: $e\n$st");
      } finally {
        // 프레임 처리 속도 안정화
        final remain = 25 - sw.elapsedMilliseconds;
        if (remain > 0) await Future.delayed(Duration(milliseconds: remain));
        _busy = false;
      }
    });
  }

  Future<void> _onRecognized(String value) async {
    await Vibration.vibrate(duration: 120);
    await _tts.speak("코드 인식 완료. 정보를 불러옵니다.");

    // ① 앞 '010' 제외 + 숫자만 정제
    String cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('010') && cleaned.length >= 16) {
      cleaned = cleaned.substring(3, 16); // ← 13자리만 추출
    }

    debugPrint("🔍 원본코드='$value' → 정제='$cleaned' len=${cleaned.length}");

    setState(() => _loading = true);
    try {
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      final url = '$baseUrl/api/v3/log/by-standard-code';
      final headers = await ApiHelper.getAuthHeaders(); // ② 인증 헤더 추가

      debugPrint("🌐 요청 URL: $url");
      debugPrint("📦 요청 데이터: {'standard_code': $cleaned}");
      debugPrint("🔑 요청 헤더: $headers");

      final dio = Dio();
      final res = await dio.post(
        url,
        data: {'standard_code': cleaned},
        options: Options(
          headers: headers, 
          validateStatus: (s) => true,
        ),
      );

      debugPrint("📡 응답 상태코드=${res.statusCode}");
      debugPrint("📡 응답 본문=${res.data}");

      if (res.statusCode == 200 && res.data?['results'] != null) {
      final results = res.data['results'] as Map<String, dynamic>;

      if (results.isEmpty) {
        await _tts.speak("결과가 없습니다.");
        _restartStreamWithHint();
        return;
      }

      final firstKey = results.keys.first;
      final firstResult = results[firstKey] ?? {};

      final permitDetail = firstResult['permit']?['permitDetail'] ?? {};
      final edrug = firstResult['edrug'] ?? {};
      final dur = firstResult['dur'] ?? {};

      // 🧩 drug_detail.dart와 동일한 구조로 변환
      final transformed = {
        "itemSeq": permitDetail["ITEM_SEQ"],
        "itemName": permitDetail["ITEM_NAME"],
        "entpName": permitDetail["ENTP_NAME"],
        "chart": permitDetail["CHART"],
        "efficacy": edrug["effect"] ?? [],
        "dosage": edrug["dosage"] ?? [],
        "precautions": edrug["precautions"] ?? [],
        "sideEffects": edrug["sideEffects"] ?? [],
        "dur": dur,
        "raw": res.data, // 필요 시 전체 원본도 함께 전달
      };

      await _tts.speak("약 정보를 찾았습니다.");

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        '/drug_detail',
        arguments: {'drugInfo': transformed},
      );
    } else {
      await _tts.speak("약 정보를 찾지 못했습니다. 상태 코드 ${res.statusCode}");
      _restartStreamWithHint();
    }
    } catch (e, st) {
      debugPrint("🚨 서버 요청 중 오류: $e\n$st");
      await _tts.speak("서버 연결에 실패했습니다.");
      _restartStreamWithHint();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  void _restartStreamWithHint() async {
    // 실패 시 다시 스트림 재개
    if (_cam != null && !_cam!.value.isStreamingImages) {
      await _cam!.startImageStream((_) {});
      _cam!.stopImageStream();
      _startStream();
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _scanner.close();
    _tts.stop();
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    if (_cam == null) return;
    final mode = _cam!.value.flashMode;
    final next = (mode == FlashMode.torch) ? FlashMode.off : FlashMode.torch;
    await _cam!.setFlashMode(next);
    debugPrint("🔦 Torch: $next");
  }

  // 길게 누르면 정지샷으로 재시도(트러블슈팅용)
  Future<void> _stillShotTry() async {
    if (_cam == null || _loading) return;
    try {
      await _cam!.stopImageStream();
      final file = await _cam!.takePicture();
      debugPrint("📸 Still path=${file.path}");

      final input = InputImage.fromFilePath(file.path);
      final codes = await _scanner.processImage(input);
      debugPrint("🧪 Still 디코드 개수: ${codes.length}");
      if (codes.isNotEmpty) {
        final val = codes.first.rawValue ?? '';
        await _onRecognized(val);
      } else {
        await _tts.speak("사진으로도 코드를 찾지 못했습니다. 각도를 바꿔 다시 시도해주세요.");
        _startStream();
      }
    } catch (e) {
      debugPrint("❌ Still 시도 오류: $e");
      _startStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlay = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.yellowAccent, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "중앙 노란 박스에 코드를 맞추고 천천히 돌려 주세요",
          style: TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          "어두우면 오른쪽 위 버튼으로 플래시를 켜세요. 길게 누르면 사진으로 재시도합니다.",
          style: TextStyle(color: Colors.white70, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("QR/바코드 인식", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _toggleTorch,
            icon: const Icon(Icons.flashlight_on, color: Colors.yellowAccent),
            tooltip: '토치 켜기/끄기',
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : GestureDetector(
              onLongPress: _stillShotTry, // 길게 누르면 스틸샷으로 시도
              child: Stack(
                children: [
                  Positioned.fill(child: CameraPreview(_cam!)),
                  if (_loading)
                    Container(
                      color: Colors.black.withOpacity(0.8),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                  if (!_loading)
                    IgnorePointer(
                      child: Center(child: overlay),
                    ),
                ],
              ),
            ),
    );
  }
}