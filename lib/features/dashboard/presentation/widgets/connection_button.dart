import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../shared/themes/app_theme.dart';
import '../../domain/connection_provider.dart';

class ConnectionButton extends ConsumerWidget {
  const ConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionProvider);
    final isConnected = connectionState.status == ConnectionStatus.connected;
    final isConnecting = connectionState.status == ConnectionStatus.connecting;

    return GestureDetector(
      onTap: isConnecting
          ? null
          : () {
              if (isConnected) {
                ref.read(connectionProvider.notifier).disconnect();
              } else {
                ref.read(connectionProvider.notifier).connect();
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isConnected
                ? [AppTheme.connectedColor, AppTheme.connectedColor.withOpacity(0.7)]
                : isConnecting
                    ? [AppTheme.connectingColor, AppTheme.connectingColor.withOpacity(0.7)]
                    : [Colors.grey.shade400, Colors.grey.shade600],
          ),
          boxShadow: [
            BoxShadow(
              color: (isConnected
                      ? AppTheme.connectedColor
                      : isConnecting
                          ? AppTheme.connectingColor
                          : Colors.grey)
                  .withOpacity(0.4),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isConnecting)
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            else
              Icon(
                isConnected ? Icons.power_settings_new : Icons.power_off,
                size: 64,
                color: Colors.white,
              ),
            const SizedBox(height: 12),
            Text(
              isConnected
                  ? '已连接'
                  : isConnecting
                      ? '连接中...'
                      : '未连接',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (connectionState.connectedNode != null) ...[
              const SizedBox(height: 4),
              Text(
                connectionState.connectedNode!.name,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ).animate(
        onPlay: (controller) => isConnecting ? controller.repeat() : null,
      ).shimmer(
        duration: isConnecting ? const Duration(seconds: 2) : Duration.zero,
        color: Colors.white.withOpacity(0.3),
      ),
    );
  }
}
