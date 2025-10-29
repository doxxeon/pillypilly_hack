import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class AccessibleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool centerTitle;

  const AccessibleAppBar({
    Key? key,
    required this.title,
    this.actions,
    this.centerTitle = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return AppBar(
          backgroundColor: theme.primaryColor,
          centerTitle: centerTitle,
          title: Semantics(
            header: true,
            label: title,
            child: Text(
              title,
              style: theme.appBarTitleStyle,
            ),
          ),
          iconTheme: IconThemeData(color: theme.textColor),
          actions: actions,
        );
      },
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
