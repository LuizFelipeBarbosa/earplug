import 'package:flutter/material.dart';

import '../widgets/common.dart';
import '../widgets/org_team_panel.dart';

/// Standalone team page. The same panel lives inside the ORGANIZATION hub;
/// this route stays for hosts and deep links that still target it.
class OrgTeamScreen extends StatelessWidget {
  const OrgTeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: const [OrgTeamPanel()],
    );
  }
}
