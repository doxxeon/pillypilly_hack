import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/theme_service.dart';
import '../../widgets/accessible_scaffold.dart';
import '../../widgets/accessible_button.dart';
import 'record.dart';

class KeepingScreen extends StatefulWidget {
  const KeepingScreen({Key? key}) : super(key: key);

  @override
  State<KeepingScreen> createState() => _KeepingScreenState();
}

class _KeepingScreenState extends State<KeepingScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AccessibleScaffold(
          title: '보관함',
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: AccessibleButton(
                  label: '검색 기록 확인하기',
                  icon: Icons.history,
                  hint: '이전에 검색한 약물 기록을 확인합니다',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RecordScreen(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}