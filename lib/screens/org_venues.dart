import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/approx_area_map.dart';
import '../widgets/common.dart';

class OrgVenuesScreen extends StatefulWidget {
  const OrgVenuesScreen({super.key});

  @override
  State<OrgVenuesScreen> createState() => _OrgVenuesScreenState();
}

class _OrgVenuesScreenState extends State<OrgVenuesScreen> {
  OrganizationDashboard? _dashboard;
  Object? _error;
  bool _loading = true;
  String? _loadedOrganizationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final organizationId = context.read<AppState>().organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _refresh();
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await app.repository.organizationDashboard(
        organizationId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _dashboard = dashboard;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venues = _dashboard?.venues ?? const <Venue>[];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Text('VENUES', style: epDisplay(size: 22)),
        const SizedBox(height: 4),
        Text(
          app.canManageOrganization(app.organizationId)
              ? 'Manage public venue profiles and private operational details.'
              : 'View public venue profiles and private operational details.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _LoadError(onRetry: _refresh)
        else if (venues.isEmpty)
          const EpCard(
            child: Text('No venues are connected to this organization.'),
          )
        else
          for (final venue in venues) ...[
            EpCard(
              key: ValueKey('org-venue-${venue.id}'),
              onTap: () =>
                  context.read<AppState>().go(Screen.orgVenueEdit, venue.id),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(venue.name, style: epDisplay(size: 17)),
                            const SizedBox(height: 4),
                            Text(
                              venue.approx.label,
                              style: Theme.of(context).textTheme.epCaption,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(
                        label: venue.verified ? 'VERIFIED' : 'SUSPENDED',
                        tone: venue.verified
                            ? EpStatusPillTone.success
                            : EpStatusPillTone.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ApproxAreaMap(
                    centroid: venue.approx.centroid,
                    label: venue.approx.label,
                    height: 130,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 56),
        const Text('Could not load venues.'),
        const SizedBox(height: 12),
        EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
      ],
    );
  }
}
