import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/connection_button.dart';
import '../widgets/status_card.dart';
import '../widgets/traffic_card.dart';
import '../widgets/quick_actions.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dashboard',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '欢迎使用 Vortex 漩涡',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  // Refresh button
                  IconButton(
                    onPressed: () {
                      // TODO: Refresh subscription
                    },
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新订阅',
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Connection button - center piece
              const Center(child: ConnectionButton()),
              const SizedBox(height: 32),

              // Status cards row
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 600) {
                    return const Row(
                      children: [
                        Expanded(child: StatusCard()),
                        SizedBox(width: 16),
                        Expanded(child: TrafficCard()),
                      ],
                    );
                  } else {
                    return const Column(
                      children: [
                        StatusCard(),
                        SizedBox(height: 16),
                        TrafficCard(),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 24),

              // Quick actions
              const QuickActions(),
            ],
          ),
        ),
      ),
    );
  }
}
