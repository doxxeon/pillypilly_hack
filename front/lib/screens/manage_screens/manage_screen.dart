import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import 'date.dart';
import 'check.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({Key? key}) : super(key: key);

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '복약 관리',
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AccessibleButton(
                  label: '복용 일정 알림',
                  icon: Icons.alarm,
                  hint: '복용 일정 알림을 설정합니다',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DateScreen()),
                    );
                  },
                ),
                const SizedBox(height: 32),
                AccessibleButton(
                  label: '복약 여부 체크',
                  icon: Icons.check,
                  hint: '복약 여부를 체크합니다',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CheckScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}