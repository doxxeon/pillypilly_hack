import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import 'accessible_app_bar.dart';

class AccessibleScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final bool centerTitle;
  final bool showAppBar;
  final Color? backgroundColor; // ✅ 추가됨

  const AccessibleScaffold({
    Key? key,
    required this.title,
    required this.body,
    this.actions,
    this.centerTitle = true,
    this.showAppBar = true,
    this.backgroundColor, // ✅ 추가됨
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return Scaffold(
          backgroundColor: backgroundColor ?? theme.backgroundColor, // ✅ 수정
          appBar: showAppBar
              ? AccessibleAppBar(
                  title: title,
                  actions: actions,
                  centerTitle: centerTitle,
                )
              : null,
          body: body,
        );
      },
    );
  }
}