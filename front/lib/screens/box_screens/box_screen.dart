import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import 'box_qr.dart';
import 'box_exp.dart'; // ✅ 유통기한 인식 페이지

class BoxScreen extends StatefulWidget {
  const BoxScreen({Key? key}) : super(key: key);

  @override
  State<BoxScreen> createState() => _BoxScreenState();
}

class _BoxScreenState extends State<BoxScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '약 상자 인식',
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ 1. QR / 바코드 인식 버튼
                  AccessibleButton(
                    label: 'QR / 바코드 인식',
                    icon: Icons.qr_code_scanner,
                    hint: '약 상자의 QR 코드나 바코드를 찍어서 의약품 상세 설명을 들려드립니다',
                    width: double.infinity,
                    height: 70,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BoxQrScreen(), // ✅ 의약품 상세설명 흐름
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 30),

                  // ✅ 2. 유통기한 인식 버튼
                  AccessibleButton(
                    label: '유통기한 인식',
                    icon: Icons.date_range,
                    hint:
                        '약 상자의 유통기한을 인식한 뒤, 오늘 날짜와 비교해서 기한이 지났는지 안내합니다',
                    width: double.infinity,
                    height: 70,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BoxExpScreen(), // ✅ 유통기한 안내 흐름
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // 💬 시각장애인용 안내 문구
                  Text(
                    '첫 번째 버튼은 QR/바코드를 찍어 약 이름과 효능, 복용법을 설명해 줍니다.\n'
                    '두 번째 버튼은 유통기한을 읽어 오늘 날짜와 비교해, 이미 지난 약인지 알려줍니다.',
                    textAlign: TextAlign.center,
                    style: theme.bodyTextStyle.copyWith(
                      fontSize: 16 * theme.fontScale,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
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