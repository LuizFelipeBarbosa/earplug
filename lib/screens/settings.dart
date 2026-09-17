import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../services/appearance_controller.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_text.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.launch});

  final ExternalUrlLauncher? launch;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  var _deleting = false;
  String? _deleteError;

  Future<void> _setAppearance(
    AppearanceController appearance,
    ThemeMode mode,
  ) async {
    final saved = await appearance.setMode(mode);
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't save appearance. It will reset when EarPlug restarts.",
        ),
      ),
    );
  }

  Future<void> _confirmDelete(AppState app) async {
    var confirmation = '';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_deleting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final matches = confirmation == 'DELETE';
            return AlertDialog(
              title: Text('DELETE ACCOUNT?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This permanently deletes your sign-in and private fan profile. Type DELETE to confirm.',
                    style: Theme.of(context).textTheme.epBody,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('delete-account-confirmation'),
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (value) =>
                        setDialogState(() => confirmation = value),
                    decoration: epInputDecoration(context, 'DELETE'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  key: const Key('cancel-delete-account'),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text('CANCEL'),
                ),
                FilledButton(
                  key: const Key('confirm-delete-account'),
                  onPressed: matches
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  style: _destructiveStyle(context),
                  child: Text('DELETE ACCOUNT'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _deleteError = null;
    });
    final deleted = await app.deleteAccount();
    if (!mounted || deleted) return;
    setState(() {
      _deleting = false;
      _deleteError =
          "Couldn't delete your account. Nothing was removed. Try again.";
    });
  }

  Widget _linkCard({
    required Key key,
    required IconData icon,
    required String title,
    String? caption,
    required VoidCallback? onTap,
  }) => EpCard(
    key: key,
    onTap: onTap,
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Icon(icon, color: context.epColors.accent),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.epLabel),
              if (caption != null) ...[
                const SizedBox(height: 2),
                Text(caption, style: Theme.of(context).textTheme.epCaption),
              ],
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: context.epColors.contentSecondary),
      ],
    ),
  );

  void _openLegal(String url) =>
      openExternalForUser(context, url, launch: widget.launch);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final appearance = context.watch<AppearanceController>();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        EpLayout.isDesktop(context) ? 0 : headerTopPad(context),
        EpLayout.gutter,
        32,
      ),
      children: [
        Row(
          children: [
            CircleIconButton(
              key: const ValueKey('settings-back-control'),
              onTap: _deleting ? null : app.back,
              tooltip: 'Back to profile',
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'SETTINGS',
                style: Theme.of(context).textTheme.epPageHeading,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const EpEyebrow('APPEARANCE'),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          key: const Key('appearance-mode'),
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('SYSTEM')),
            ButtonSegment(value: ThemeMode.light, label: Text('LIGHT')),
            ButtonSegment(value: ThemeMode.dark, label: Text('DARK')),
          ],
          selected: {appearance.mode},
          showSelectedIcon: false,
          onSelectionChanged: _deleting
              ? null
              : (selection) => _setAppearance(appearance, selection.single),
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 48)),
          ),
        ),
        const SizedBox(height: 20),
        const EpEyebrow('PRIVACY'),
        const SizedBox(height: 8),
        _linkCard(
          key: const Key('privacy-settings-entry'),
          icon: Icons.lock_outline,
          title: 'PROFILE PREFERENCES',
          caption:
              'Your fan profile stays private. Choose how location and followed bands personalize it.',
          onTap: _deleting ? null : app.openEditProfile,
        ),
        const SizedBox(height: 18),
        const EpEyebrow('LEGAL'),
        const SizedBox(height: 8),
        _linkCard(
          key: const Key('legal-terms'),
          icon: Icons.description_outlined,
          title: 'TERMS OF SERVICE',
          caption: legalEffective ? null : 'Draft — not yet effective',
          onTap: _deleting ? null : () => _openLegal(legalTermsUrl),
        ),
        const SizedBox(height: 10),
        _linkCard(
          key: const Key('legal-privacy'),
          icon: Icons.privacy_tip_outlined,
          title: 'PRIVACY POLICY',
          caption: legalEffective ? null : 'Draft — not yet effective',
          onTap: _deleting ? null : () => _openLegal(legalPrivacyUrl),
        ),
        const SizedBox(height: 10),
        _linkCard(
          key: const Key('legal-agreements'),
          icon: Icons.handshake_outlined,
          title: 'AGREEMENTS',
          caption: legalEffective
              ? 'Organizer, artist and host agreements'
              : 'Draft — not yet effective',
          // The organizer agreement is the entry point for the agreements group.
          onTap: _deleting
              ? null
              : () => _openLegal(legalOrganizerAgreementUrl),
        ),
        const SizedBox(height: 18),
        const EpEyebrow('SESSION'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('settings-sign-out'),
          onPressed: _deleting ? null : app.signOut,
          style: ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(
              context.epColors.destructive,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? context.epColors.contentDisabled
                    : context.epColors.destructive,
                width: 1.5,
              ),
            ),
          ),
          icon: Icon(Icons.logout),
          label: Text('SIGN OUT'),
        ),
        const SizedBox(height: 28),
        Container(
          key: const Key('account-danger-zone'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.epColors.destructive.withValues(alpha: .08),
            border: Border.all(color: context.epColors.destructive),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DANGER ZONE',
                style: Theme.of(context).textTheme.epLabel.copyWith(
                  color: context.epColors.destructive,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Account deletion is permanent and separate from signing out.',
                style: Theme.of(context).textTheme.epCaption,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('delete-account'),
                onPressed: _deleting ? null : () => _confirmDelete(app),
                style: _destructiveStyle(context),
                child: Text(_deleting ? 'DELETING…' : 'DELETE ACCOUNT'),
              ),
              if (_deleteError case final error?) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const Key('delete-account-error'),
                    style: Theme.of(context).textTheme.epBody.copyWith(
                      color: context.epColors.destructive,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

ButtonStyle _destructiveStyle(BuildContext context) => ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(context.epColors.destructive),
  foregroundColor: WidgetStatePropertyAll(context.epColors.onAccent),
);
