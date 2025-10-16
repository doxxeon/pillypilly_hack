import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

class BoxQrScreen extends StatefulWidget {
  const BoxQrScreen({super.key});

  @override
  State<BoxQrScreen> createState() => _BoxQrScreenState();
}

class _BoxQrScreenState extends State<BoxQrScreen> {
  CameraController? _cameraController;
  late final BarcodeScanner _barcodeScanner;
  bool _isProcessing = false;
  bool _isInitialized = false;

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  Map<String, dynamic>? _drugInfo;
  String? _barcode;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _barcodeScanner =
        BarcodeScanner(formats: [BarcodeFormat.qrCode, BarcodeFormat.ean13, BarcodeFormat.code128]);
    _announceIntro();
  }

  Future<void> _announceIntro() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.45);
    await _tts.speak(
      "약 상자의 표면을 천천히 돌리면서 비춰주세요. QR 코드나 바코드가 인식되면 삑 소리와 함께 안내가 시작됩니다.",
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setZoomLevel(1.2);

      _isInitialized = true;
      if (mounted) setState(() {});
      _startImageStream();
    } catch (e) {
      debugPrint("❌ 카메라 초기화 실패: $e");
      await _tts.speak("카메라를 초기화하는 중 오류가 발생했습니다.");
    }
  }

  void _startImageStream() {
    _cameraController?.startImageStream((image) async {
      if (_isProcessing || _barcode != null) return;
      _isProcessing = true;

      try {
        debugPrint("📸 프레임 수신 중... width=${image.width}, height=${image.height}");
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }

        final bytes = allBytes.done().buffer.asUint8List();

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.yuv420,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );

        final barcodes = await _barcodeScanner.processImage(inputImage);
        debugPrint("🔍 감지된 바코드 수: ${barcodes.length}");

        if (barcodes.isNotEmpty) {
          final code = barcodes.first.rawValue;
          if (code != null && code.isNotEmpty) {
            debugPrint("✅ 감지된 코드: $code");
            await _handleBarcode(code);
          }
        }
      } catch (e) {
        debugPrint("❌ QR 인식 오류: $e");
      } finally {
        _isProcessing = false;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    });
  }

  Future<void> _handleBarcode(String code) async {
    debugPrint("🛑 인식 완료 → 스트림 중지");
    await _cameraController?.stopImageStream();

    // ✅ 삑 소리 + 진동
    try {
      await _player.play(AssetSource('sounds/beep.mp3'));
    } catch (e) {
      debugPrint("⚠️ 사운드 재생 실패: $e");
    }
    await Vibration.vibrate(duration: 120);
    await _tts.speak("코드 인식 완료. 정보를 불러옵니다.");

    // ✅ QR 코드 길이 15자리면 앞의 '00' 제거하고 13자리만 사용
    String processedCode = code;
    if (code.length == 15 && code.startsWith("00")) {
      processedCode = code.substring(2);
      debugPrint("🔢 변환된 코드: $processedCode (원본: $code)");
    }

    setState(() => _barcode = processedCode);
    await _fetchDrugInfo(processedCode);
  }

  Future<void> _fetchDrugInfo(String barcode) async {
    try {
      final dio = Dio();
      final baseUrl = dotenv.env['API_BASE_URL'] ?? '';
      if (baseUrl.isEmpty) {
        debugPrint("⚠️ API_BASE_URL 누락됨 (.env 확인 필요)");
        await _tts.speak("서버 주소를 불러올 수 없습니다. 설정을 확인해주세요.");
        return;
      }

      final url = '$baseUrl/drug/info';
      debugPrint("🌐 약 정보 요청 중: $url?barcode=$barcode");

      final response = await dio.get(url, queryParameters: {'barcode': barcode});

      if (response.statusCode == 200 && response.data != null) {
        debugPrint("✅ 서버 응답 성공: ${response.data}");
        setState(() => _drugInfo = response.data);
        await _tts.speak("약 정보 불러오기 완료.");
      } else {
        debugPrint("⚠️ 서버 응답 실패: ${response.statusCode}");
        await _tts.speak("서버에서 약 정보를 찾을 수 없습니다.");
      }
    } catch (e) {
      debugPrint("❌ 서버 통신 오류: $e");
      await _tts.speak("약 정보를 불러오지 못했습니다. 인터넷 연결을 확인해주세요.");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _barcodeScanner.close();
    _tts.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isHighContrast = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isHighContrast ? Colors.black : const Color(0xFF1E1E1E);
    final accentColor = isHighContrast ? Colors.amberAccent : Colors.yellowAccent;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("QR / 바코드 인식"),
        backgroundColor: bgColor,
        foregroundColor: accentColor,
        centerTitle: true,
      ),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              alignment: Alignment.center,
              children: [
                CameraPreview(_cameraController!),
                if (_barcode == null)
                  Align(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_scanner, size: 120, color: Colors.white54),
                        const SizedBox(height: 20),
                        Text(
                          "상자 표면을 천천히 돌려서 비춰주세요",
                          style: TextStyle(color: accentColor, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                else
                  _ResultCard(barcode: _barcode!, drugInfo: _drugInfo, accentColor: accentColor),
              ],
            ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String barcode;
  final Map<String, dynamic>? drugInfo;
  final Color accentColor;

  const _ResultCard({
    required this.barcode,
    required this.drugInfo,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('코드 번호: $barcode',
                style: const TextStyle(color: Colors.black, fontSize: 18)),
            const SizedBox(height: 8),
            if (drugInfo != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('약 이름: ${drugInfo?["itemName"] ?? "정보 없음"}',
                      style: const TextStyle(color: Colors.black, fontSize: 16)),
                  Text('제조사: ${drugInfo?["entpName"] ?? "정보 없음"}',
                      style: const TextStyle(color: Colors.black, fontSize: 16)),
                  Text('효능: ${drugInfo?["effect"] ?? "정보 없음"}',
                      style: const TextStyle(color: Colors.black, fontSize: 16)),
                ],
              )
            else
              const Text('약 정보를 불러오는 중...',
                  style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}