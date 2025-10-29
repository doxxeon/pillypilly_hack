import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'api_services/token_service.dart';
import 'screens/main_screen.dart';
import 'services/theme_service.dart';
import 'screens/details/drug_detail.dart'; // ✅ 상세화면 import 추가

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  final authService = AuthService();
  final success = await authService.fetchToken();

  if (success) {
    debugPrint("✅ 토큰 발급 성공!");
  } else {
    debugPrint("⚠️ 토큰 발급 실패. 서버 확인 필요.");
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeService.instance,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PillyPilly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),

      routes: {
      '/': (context) => const MainScreen(),
      '/drug_detail': (context) {
        final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
        return DrugDetailScreen(initialDrugInfo: args['drugInfo']);
      },
    },

      initialRoute: '/', // 기본 진입점
    );
  }
}