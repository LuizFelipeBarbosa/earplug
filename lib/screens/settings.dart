import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  var _deleting = false;
  String? _deleteError;

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
              title: const Text('DELETE ACCOUNT?'),
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
                    decoration: epInputDecoration('DELETE'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  key: const Key('cancel-delete-account'),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  key: const Key('confirm-delete-account'),
                  onPressed: matches
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  style: const ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Ep.destructive),
                    foregroundColor: WidgetStatePropertyAll(Colors.white),
                  ),
                  child: const Text('DELETE ACCOUNT'),
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ListView(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 32),
      children: [
        Row(
          children: [
            CircleIconButton(
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
        const SectionLabel('PRIVACY'),
        const SizedBox(height: 8),
        EpCard(
          key: const Key('privacy-settings-entry'),
          onTap: _deleting ? null : app.openEditProfile,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: Ep.accent),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROFILE PREFERENCES',
                      style: Theme.of(context).textTheme.epLabel,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your fan profile stays private. Choose how location and followed bands personalize it.',
                      style: Theme.of(context).textTheme.epCaption,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Ep.contentSecondary),
            ],
          ),
        ),
        if (app.profileTutorialAvailable) ...[
          const SizedBox(height: 18),
          const SectionLabel('PROFILE HELP'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('replay-profile-tutorial'),
            onPressed: _deleting ? null : app.replayProfileTutorial,
            icon: const Icon(Icons.replay),
            label: const Text('REPLAY PROFILE TUTORIAL'),
          ),
        ],
        const SizedBox(height: 18),
        const SectionLabel('SESSION'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('settings-sign-out'),
          onPressed: _deleting ? null : app.signOut,
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Ep.destructive),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? Ep.contentDisabled
                    : Ep.destructive,
                width: 1.5,
              ),
            ),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('SIGN OUT'),
        ),
        const SizedBox(height: 28),
        Container(
          key: const Key('account-danger-zone'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Ep.destructive.withValues(alpha: .08),
            border: Border.all(color: Ep.destructive),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'DANGER ZONE',
                style: Theme.of(
                  context,
                ).textTheme.epLabel.copyWith(color: Ep.destructive),
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
                style: const ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Ep.destructive),
                  foregroundColor: WidgetStatePropertyAll(Colors.white),
                ),
                child: Text(_deleting ? 'DELETING…' : 'DELETE ACCOUNT'),
              ),
              if (_deleteError case final error?) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    key: const Key('delete-account-error'),
                    style: Theme.of(
                      context,
                    ).textTheme.epBody.copyWith(color: Ep.destructive),
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
