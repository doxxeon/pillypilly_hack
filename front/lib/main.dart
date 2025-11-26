import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'api_services/token_service.dart';
import 'screens/main_screen.dart';
import 'screens/details/drug_detail.dart';
import 'services/theme_service.dart';
import 'screens/upload_page_screens/prescription_result.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // ✅ 환경 변수 로드 (.env 파일)
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("⚠️ .env 파일 로드 실패: $e");
  }

  // ✅ ThemeService 먼저 생성 및 설정 로드
  final themeService = ThemeService();
  try {
    await themeService.loadSettings();
    debugPrint("✅ ThemeService 설정 로드 완료");
  } catch (e) {
    debugPrint("⚠️ ThemeService 설정 로드 실패: $e");
  }

  // ✅ 토큰 확인 및 필요시 발급 (비동기로 처리, 실패해도 앱은 시작)
  _initializeToken().catchError((e) {
    debugPrint("⚠️ 토큰 초기화 오류: $e");
  });

  // ✅ ThemeService Provider 등록 및 앱 시작
  runApp(
    ChangeNotifierProvider.value(
      value: themeService,
      child: const MyApp(),
    ),
  );
}

Future<void> _initializeToken() async {
  try {
    final authService = AuthService();
    final existingToken = await authService.getToken();
    
    if (existingToken == null) {
      // 토큰이 없으면 새로 발급
      final success = await authService.fetchToken();
      if (success) {
        debugPrint("✅ 새 토큰 발급 성공!");
      } else {
        debugPrint("⚠️ 토큰 발급 실패. 서버 확인 필요.");
      }
    } else {
      // 기존 토큰이 있으면 유효성 확인 후 필요시 갱신
      final validToken = await authService.getValidToken();
      if (validToken != null) {
        debugPrint("✅ 기존 토큰 유효 또는 갱신 완료");
      } else {
        debugPrint("⚠️ 토큰 갱신 실패. 새로 발급 시도...");
        final success = await authService.fetchToken();
        if (success) {
          debugPrint("✅ 새 토큰 발급 성공!");
        } else {
          debugPrint("⚠️ 토큰 발급 실패. 서버 확인 필요.");
        }
      }
    }
  } catch (e) {
    debugPrint("⚠️ 토큰 초기화 중 오류: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return MaterialApp(
          title: 'PillyPilly',
          debugShowCheckedModeBanner: false,

          // ✅ ThemeService 기반 동적 테마 반영
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: theme.primaryColor,
              brightness:
                  theme.isHighContrastEnabled ? Brightness.dark : Brightness.light,
            ),
            scaffoldBackgroundColor: theme.backgroundColor,
            appBarTheme: AppBarTheme(
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
              centerTitle: true,
              titleTextStyle: theme.appBarTitleStyle,
            ),
          ),

          // ✅ 라우트 정의
          routes: {
            '/': (context) => const SplashScreen(),
            '/main': (context) => const MainScreen(),
            '/drug_detail': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              return DrugDetailScreen(
                initialDrugInfo: args,
              );
            },
            '/pill_capture': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final prescriptionId = (args?['prescriptionId'] ?? '').toString();
              final totalCount = (args?['totalCount'] ?? 0) as int;

              return Scaffold(
                appBar: AppBar(
                  title: const Text("알약 촬영"),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.camera_alt, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          '처방전 ID: $prescriptionId',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '촬영할 알약 개수: ${totalCount}개',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'pill_capture.dart 화면과 연동하기 전 임시 화면입니다.\n'
                          '여기에서 실제 카메라 촬영 로직을 구현하거나,\n'
                          '기존 pill_capture.dart 위젯으로 교체할 수 있습니다.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            '/prescription-result': (context) {
              final args =
                  ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final prescriptionId = (args?['prescriptionId'] ?? '').toString();
              final totalCount = (args?['totalCount'] ?? 0) as int;

              return PrescriptionResultPage(
                prescriptionId: prescriptionId,
                totalCount: totalCount,
              );
            },
          },

          initialRoute: '/', // 기본 진입점
        );
      },
    );
  }
}