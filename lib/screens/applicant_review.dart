import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/common.dart';
import '../widgets/ep_text.dart';

/// Placeholder for reviewing one application; the real screen replaces it.
class ApplicantReviewScreen extends StatelessWidget {
  const ApplicantReviewScreen({super.key, required this.applicationId});

  final String applicationId;

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
            key: const Key('applicant-review-back'),
            onPressed: app.back,
          ),
        ),
        const EpDisplay('Review'),
      ],
    );
  }
}
