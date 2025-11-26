import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';

class LoadingWidget extends StatelessWidget {
  final String message;
  final bool showProgressIndicator;

  const LoadingWidget({
    Key? key,
    this.message = '검색 중입니다...',
    this.showProgressIndicator = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return Container(
          color: theme.backgroundColor,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                // 🔥 overflow 방지
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (showProgressIndicator) ...[
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.primaryColor,
                      ),
                      strokeWidth: 3.0,
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    message,
                    style: theme.buttonTextStyle.copyWith(
                      fontSize: 18 * theme.fontScale,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '잠시만 기다려주세요',
                    style: theme.subtitleTextStyle.copyWith(
                      fontSize: 14 * theme.fontScale,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
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

class CustomErrorWidget extends StatelessWidget {
  final String message;
  final String? details;
  final VoidCallback? onRetry;

  const CustomErrorWidget({
    Key? key,
    required this.message,
    this.details,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, theme, child) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, // ✅ overflow 방지
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[400],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '오류가 발생했습니다',
                    style: theme.titleStyle.copyWith(
                      fontSize: 24 * theme.fontScale,
                      color: Colors.red[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: theme.bodyTextStyle.copyWith(
                      fontSize: 16 * theme.fontScale,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (details != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      details!,
                      style: theme.subtitleTextStyle.copyWith(
                        fontSize: 14 * theme.fontScale,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (onRetry != null)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        '다시 시도',
                        style: theme.buttonTextStyle.copyWith(
                          fontSize: 16 * theme.fontScale,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: theme.buttonTextColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: onRetry,
                    ),
            ],
          ),
        );
      },
    );
  }
}