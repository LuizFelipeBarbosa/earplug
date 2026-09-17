import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_text.dart';
import '../widgets/join_flow.dart';
import '../widgets/opportunity_labels.dart';

class OrgJoinScreen extends StatefulWidget {
  const OrgJoinScreen({super.key, required this.token});

  final String token;

  @override
  State<OrgJoinScreen> createState() => _OrgJoinScreenState();
}

class _OrgJoinScreenState extends State<OrgJoinScreen> {
  OrganizationInviteResolution? _resolution;
  String? _error;
  bool _loading = true;
  bool _accepting = false;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resolution = await context
          .read<AppState>()
          .repository
          .resolveOrganizationInvite(widget.token);
      if (!mounted) return;
      setState(() {
        _resolution = resolution;
        _loading = false;
        if (resolution == null) {
          _error = 'This invitation is invalid, expired, or revoked.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not check this invitation. Please try again later.';
      });
    }
  }

  Future<void> _accept() async {
    final app = context.read<AppState>();
    if (_accepting || _resolution == null) return;
    if (!app.authed) {
      app.needAuth(PendingAuth(PendingKind.orgJoin, widget.token));
      return;
    }
    setState(() => _accepting = true);
    try {
      final acceptance = await app.repository.acceptOrganizationInvite(
        widget.token,
      );
      if (!mounted) return;
      if (!acceptance.membershipCreated) {
        app.say('You are already a member.');
      }
      setState(() {
        _accepted = true;
        _accepting = false;
      });
      app.switchToOrganization(acceptance.organizationId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _error = 'Could not accept this invitation. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ColoredBox(
      color: context.epColors.background,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.close,
                    onTap: app.canGoBack ? app.back : app.toFanView,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ORGANIZATION INVITATION',
                      style: Theme.of(context).textTheme.epSectionHeading,
                    ),
                  ),
                ],
              ),
            ),
            const EpHairline(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _body(app),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(AppState app) {
    if (_loading) {
      return const JoinLoading(key: ValueKey('org-join-loading'));
    }
    if (_accepted) {
      final resolution = _resolution;
      return JoinAccepted(
        key: const ValueKey('org-join-accepted'),
        title: resolution == null
            ? 'Organization joined.'
            : 'You joined ${resolution.organizationName}.',
        buttonLabel: 'OPEN ORGANIZER DASHBOARD',
        onDashboard: () {
          final organizationId = _resolution?.organizationId;
          if (organizationId != null) app.switchToOrganization(organizationId);
        },
      );
    }
    if (_error case final error?) {
      return JoinError(
        key: const ValueKey('org-join-error'),
        message: error,
        actionLabel: 'BACK TO EARPLUG',
        onAction: app.toFanView,
      );
    }
    final resolution = _resolution!;
    return JoinConfirmation(
      key: const ValueKey('org-join-confirmation'),
      leading: Icon(
        Icons.storefront_outlined,
        size: 68,
        color: context.epColors.accent,
      ),
      title:
          'Join ${resolution.organizationName} as ${organizationRoleLabel(resolution.role)}',
      titleSize: 23,
      body:
          'This role gives you access to the organization\'s marketplace tools.',
      signedIn: app.authed,
      accepting: _accepting,
      confirmLabel: 'ACCEPT',
      confirmKey: const Key('org-join-accept'),
      onConfirm: _accept,
    );
  }
}
