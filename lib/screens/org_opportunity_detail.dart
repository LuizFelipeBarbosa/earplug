import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/common.dart';
import '../widgets/ep_text.dart';

/// Placeholder for an organizer's own opportunity; the real detail replaces it.
class OrgOpportunityDetailScreen extends StatelessWidget {
  const OrgOpportunityDetailScreen({super.key, required this.opportunityId});

  final String opportunityId;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(
            key: const Key('org-opportunity-back'),
            onPressed: app.back,
          ),
        ),
        const EpDisplay('Opportunity'),
      ],
    );
  }
}
