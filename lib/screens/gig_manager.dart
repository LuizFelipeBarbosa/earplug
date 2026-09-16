import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/band_applications_tab.dart';
import '../widgets/band_discover_tab.dart';
import '../widgets/band_my_gigs_tab.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';

class GigManagerScreen extends StatefulWidget {
  const GigManagerScreen({super.key});

  @override
  State<GigManagerScreen> createState() => _GigManagerScreenState();
}

class _GigManagerScreenState extends State<GigManagerScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      unawaited(app.refreshMyApplications());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      children: [
        SizedBox(height: headerTopPad(context)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
          child: Row(
            key: const Key('band-gigs-header'),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const EpDisplay('Gigs', key: Key('band-gigs-title'), size: 44),
              if (app.isAdminOf(app.bandId))
                EpPill(
                  key: const Key('band-gigs-new'),
                  label: '+ New gig',
                  variant: EpPillVariant.outline,
                  size: EpPillSize.chip,
                  onPressed: app.startGigCreate,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
          child: EpSegmentTabs(
            key: const Key('band-gigs-tabs'),
            labels: const ['My gigs', 'Discover', 'Applications'],
            selected: _tab,
            onSelect: (i) => setState(() => _tab = i),
            scrollable: false,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_tab) {
            0 => BandMyGigsTab(onDiscover: () => setState(() => _tab = 1)),
            1 => const BandDiscoverTab(),
            _ => const BandApplicationsTab(),
          },
        ),
      ],
    );
  }
}
