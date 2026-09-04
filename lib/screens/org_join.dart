import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
                      style: epDisplay(size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.epColors.border),
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
      return const _JoinLoading(key: ValueKey('org-join-loading'));
    }
    if (_accepted) {
      return _JoinAccepted(
        key: const ValueKey('org-join-accepted'),
        resolution: _resolution,
        onDashboard: () {
          final organizationId = _resolution?.organizationId;
          if (organizationId != null) app.switchToOrganization(organizationId);
        },
      );
    }
    if (_error case final error?) {
      return _JoinError(
        key: const ValueKey('org-join-error'),
        message: error,
        onBack: app.toFanView,
      );
    }
    return _JoinConfirmation(
      key: const ValueKey('org-join-confirmation'),
      resolution: _resolution!,
      signedIn: app.authed,
      accepting: _accepting,
      onConfirm: _accept,
    );
  }
}

class _JoinLoading extends StatelessWidget {
  const _JoinLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'CHECKING INVITATION…',
          style: epText(
            size: 11,
            weight: FontWeight.w900,
            letterSpacing: 1,
            color: context.epColors.contentSecondary,
          ),
        ),
      ],
    );
  }
}

class _JoinConfirmation extends StatelessWidget {
  const _JoinConfirmation({
    super.key,
    required this.resolution,
    required this.signedIn,
    required this.accepting,
    required this.onConfirm,
  });

  final OrganizationInviteResolution resolution;
  final bool signedIn;
  final bool accepting;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.storefront_outlined,
          size: 68,
          color: context.epColors.accent,
        ),
        const SizedBox(height: 18),
        Text(
          'Join ${resolution.organizationName} as ${_roleLabel(resolution.role)}',
          textAlign: TextAlign.center,
          style: epDisplay(size: 23),
        ),
        const SizedBox(height: 9),
        Text(
          'This role gives you access to the organization\'s marketplace tools.',
          textAlign: TextAlign.center,
          style: epText(
            size: 13,
            color: context.epColors.contentSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          signedIn
              ? 'You will only join after you confirm below.'
              : 'Sign in first, then return here to confirm. You will not join automatically.',
          textAlign: TextAlign.center,
          style: epText(
            size: 11,
            color: context.epColors.contentDisabled,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),
        EpButton(
          accepting
              ? 'JOINING…'
              : signedIn
              ? 'ACCEPT'
              : 'SIGN IN TO JOIN',
          key: const Key('org-join-accept'),
          kind: accepting ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: accepting ? null : onConfirm,
        ),
      ],
    );
  }
}

class _JoinAccepted extends StatelessWidget {
  const _JoinAccepted({
    super.key,
    required this.resolution,
    required this.onDashboard,
  });

  final OrganizationInviteResolution? resolution;
  final VoidCallback onDashboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle, size: 62, color: context.epColors.accent),
        const SizedBox(height: 18),
        Text(
          resolution == null
              ? 'Organization joined.'
              : 'You joined ${resolution!.organizationName}.',
          textAlign: TextAlign.center,
          style: epDisplay(size: 23),
        ),
        const SizedBox(height: 8),
        Text(
          'Your membership is active.',
          textAlign: TextAlign.center,
          style: epText(size: 12.5, color: context.epColors.contentSecondary),
        ),
        const SizedBox(height: 22),
        EpButton('OPEN ORGANIZER DASHBOARD', onTap: onDashboard),
      ],
    );
  }
}

class _JoinError extends StatelessWidget {
  const _JoinError({super.key, required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.link_off,
          size: 54,
          color: context.epColors.contentSecondary,
        ),
        const SizedBox(height: 16),
        Text(
          'Invitation unavailable',
          textAlign: TextAlign.center,
          style: epDisplay(size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: epText(
            size: 12.5,
            color: context.epColors.contentSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        EpButton('BACK TO EARPLUG', kind: EpButtonKind.outline, onTap: onBack),
      ],
    );
  }
}

String _roleLabel(OrganizationRole role) => switch (role) {
  OrganizationRole.owner => 'Owner',
  OrganizationRole.manager => 'Manager',
  OrganizationRole.finance => 'Finance',
  OrganizationRole.door => 'Door',
};
