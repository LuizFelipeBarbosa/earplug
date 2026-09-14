import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/ep_text.dart';

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Column(
      key: const Key('people-screen'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            EpLayout.gutter,
            MediaQuery.paddingOf(context).top + 22,
            EpLayout.gutter,
            0,
          ),
          child: EpIconPill(
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: app.back,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const EpDisplay('People', size: 32),
              const SizedBox(height: 12),
              Text(
                'Coming soon.',
                style: Theme.of(
                  context,
                ).textTheme.epBody.copyWith(color: context.epColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
