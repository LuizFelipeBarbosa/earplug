import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/appearance_controller.dart';
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
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      context.epColors.destructive,
                    ),
                    foregroundColor: WidgetStatePropertyAll(Colors.white),
                  ),
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final appearance = context.watch<AppearanceController>();
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
        const SectionLabel('APPEARANCE'),
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
        const SectionLabel('PRIVACY'),
        const SizedBox(height: 8),
        EpCard(
          key: const Key('privacy-settings-entry'),
          onTap: _deleting ? null : app.openEditProfile,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: context.epColors.accent),
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
              Icon(
                Icons.chevron_right,
                color: context.epColors.contentSecondary,
              ),
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
            icon: Icon(Icons.replay),
            label: Text('REPLAY PROFILE TUTORIAL'),
          ),
        ],
        const SizedBox(height: 18),
        const SectionLabel('SESSION'),
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
            borderRadius: BorderRadius.circular(14),
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
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(
                    context.epColors.destructive,
                  ),
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
