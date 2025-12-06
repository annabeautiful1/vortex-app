import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/connection_button.dart';
import '../widgets/status_card.dart';
import '../widgets/traffic_card.dart';
import '../widgets/quick_actions.dart';
import '../widgets/realtime_traffic_card.dart';
import '../../../../shared/themes/app_theme.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
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
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ).animate().fadeIn().slideX(begin: -0.1, end: 0),
                      const SizedBox(height: 4),
                      Text(
                        'Welcome back to Vortex',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ).animate().fadeIn(delay: 100.ms).slideX(begin: -0.1, end: 0),
                    ],
                  ),
                  // Refresh button
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.1),
                      ),
                    ),
                    child: IconButton(
                      onPressed: () {
                        // TODO: Refresh subscription
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh Subscription',
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ).animate().fadeIn(delay: 200.ms).scale(),
                ],
              ),
              const SizedBox(height: 48),

              // Connection button - center piece
              const Center(child: ConnectionButton())
                  .animate()
                  .fadeIn(delay: 300.ms)
                  .scale(curve: Curves.easeOutBack),
              const SizedBox(height: 48),

              // Status cards row
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 900) {
                    // Wide screen: 3 columns
                    return Row(
                      children: [
                        Expanded(child: _animateCard(const StatusCard(), 400)),
                        const SizedBox(width: 24),
                        Expanded(child: _animateCard(const RealtimeTrafficCard(), 500)),
                        const SizedBox(width: 24),
                        Expanded(child: _animateCard(const TrafficCard(), 600)),
                      ],
                    );
                  } else if (constraints.maxWidth > 600) {
                    // Medium screen: 2 rows
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _animateCard(const StatusCard(), 400)),
                            const SizedBox(width: 24),
                            Expanded(child: _animateCard(const RealtimeTrafficCard(), 500)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _animateCard(const TrafficCard(), 600),
                      ],
                    );
                  } else {
                    // Narrow screen: single column
                    return Column(
                      children: [
                        _animateCard(const StatusCard(), 400),
                        const SizedBox(height: 24),
                        _animateCard(const RealtimeTrafficCard(), 500),
                        const SizedBox(height: 24),
                        _animateCard(const TrafficCard(), 600),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 32),

              // Quick actions
              _animateCard(const QuickActions(), 700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animateCard(Widget child, int delayMs) {
    return child.animate().fadeIn(delay: delayMs.ms).slideY(begin: 0.1, end: 0);
  }
}
