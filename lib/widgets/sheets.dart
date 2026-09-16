import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'ep_sheet.dart';

/// Shared visual chrome for bottom sheets presented by [showEpSheet].
class EpSheetShell extends StatelessWidget {
  const EpSheetShell({
    super.key,
    required this.padding,
    this.backgroundColor,
    this.borderColor,
    this.topRadius = 0,
    this.handleColor,
    this.handleBottomSpacing = 10,
    required this.header,
    required this.children,
    this.heightFactor,
    this.maxHeightFactor,
    this.scrollable = false,
    this.mainAxisSize = MainAxisSize.max,
  }) : assert(heightFactor == null || maxHeightFactor == null);

  final EdgeInsetsGeometry padding;

  /// Colors default to the shared sheet background and top hairline.
  final Color? backgroundColor;
  final Color? borderColor;
  final double topRadius;
  final Color? handleColor;
  final double handleBottomSpacing;
  final Widget header;
  final List<Widget> children;
  final double? heightFactor;
  final double? maxHeightFactor;
  final bool scrollable;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final colors = context.epColors;
    final content = Column(
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: handleColor ?? colors.outline),
          ),
        ),
        SizedBox(height: handleBottomSpacing),
        header,
        ...children,
      ],
    );

    return SafeArea(
      top: false,
      child: Container(
        height: heightFactor == null ? null : screenHeight * heightFactor!,
        constraints: maxHeightFactor == null
            ? null
            : BoxConstraints(maxHeight: screenHeight * maxHeightFactor!),
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor ?? colors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
          border: Border(top: BorderSide(color: borderColor ?? colors.line)),
        ),
        // The shell paints an opaque surface above BottomSheet's Material, so
        // ink from rows needs its own transparent Material to show through.
        child: Material(
          type: MaterialType.transparency,
          child: scrollable ? SingleChildScrollView(child: content) : content,
        ),
      ),
    );
  }
}

/// Keyboard-aware chrome for a form sheet: an uppercase [title] with a
/// Close button (or [trailing]) above [child]. Unlike [EpSheetShell] it has no
/// drag handle and rises with the on-screen keyboard. By default the body
/// scrolls and clears the bottom system inset so its last control stays out of
/// the home-indicator gesture zone.
class EpFormSheet extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  /// Sheets that own their own scrolling (the calendar) lay out their body.
  final bool padBody;

  const EpFormSheet({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padBody = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      decoration: BoxDecoration(
        color: context.epColors.background,
        border: Border(top: BorderSide(color: context.epColors.line)),
      ),
      // Same as EpSheetShell: the surface above sits over BottomSheet's
      // Material, so list tiles and rows need this Material for their ink.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      semanticsLabel: title,
                      style: Theme.of(context).textTheme.epSheetTitle,
                    ),
                  ),
                  trailing ??
                      Tooltip(
                        message: 'Close',
                        excludeFromSemantics: true,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Close'.toUpperCase(),
                            semanticsLabel: 'Close',
                            style: Theme.of(context).textTheme.epLabel.copyWith(
                              color: context.epColors.ink,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
            if (padBody)
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: child,
                ),
              )
            else
              Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// Full-width option row with a selection indicator and bottom hairline.
class EpOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool titleCaps;

  const EpOptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.titleCaps = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.epColors;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? colors.accent : null,
                    border: selected ? null : Border.all(color: colors.outline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleCaps ? title.toUpperCase() : title,
                        semanticsLabel: title,
                        style: textTheme.epBody.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: textTheme.epCaption.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final Widget leading;
  final VoidCallback onTap;
  final double verticalPadding;

  const _SheetOption({
    required this.leading,
    required this.onTap,
    this.verticalPadding = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.epColors.line)),
          ),
          child: leading,
        ),
      ),
    );
  }
}

/// Callback-only description of an overflow-sheet action.
class EpActionSheetItem {
  const EpActionSheetItem({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool destructive;
}

/// Generic action-sheet presentation. Domain rules stay with the caller.
class EpActionSheet extends StatelessWidget {
  const EpActionSheet({super.key, required this.header, required this.items});

  final String header;
  final List<EpActionSheetItem> items;

  @override
  Widget build(BuildContext context) {
    final firstDestructive = items.indexWhere((item) => item.destructive);
    return EpSheetShell(
      padding: const EdgeInsets.all(20),
      handleBottomSpacing: 14,
      mainAxisSize: MainAxisSize.min,
      header: Text(
        header.toUpperCase(),
        semanticsLabel: header,
        style: Theme.of(context).textTheme.epSection,
      ),
      children: [
        const SizedBox(height: 8),
        for (var index = 0; index < items.length; index++) ...[
          if (index == firstDestructive)
            SizedBox(
              height: 1,
              child: ColoredBox(color: context.epColors.line),
            ),
          _ActionSheetRow(item: items[index]),
        ],
      ],
    );
  }
}

class _ActionSheetRow extends StatelessWidget {
  const _ActionSheetRow({required this.item});

  final EpActionSheetItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.destructive
        ? context.epColors.destructive
        : context.epColors.ink;
    return Semantics(
      button: true,
      enabled: item.onPressed != null,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: item.onPressed == null
            ? null
            : () {
                Navigator.of(context).pop();
                item.onPressed!();
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.epColors.line)),
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 16, color: color),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: Theme.of(
                    context,
                  ).textTheme.epBody.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showEpActionSheet(
  BuildContext context, {
  required String header,
  required List<EpActionSheetItem> items,
}) {
  return showEpSheet(
    context,
    (_) => EpActionSheet(header: header, items: items),
  );
}

// ============================ view switcher ============================

OrganizationApplication? _organizerApplication(AppState app) {
  final application = app.myOrganizationApplication;
  return application?.kind == ApplicationKind.host ? null : application;
}

OrganizationApplication? _hostApplication(AppState app) {
  final application = app.myOrganizationApplication;
  return application?.kind == ApplicationKind.host ? application : null;
}

bool _applicationInProgress(OrganizationApplication? application) =>
    switch (application?.status) {
      OrganizationApplicationStatus.draft ||
      OrganizationApplicationStatus.submitted ||
      OrganizationApplicationStatus.underReview ||
      OrganizationApplicationStatus.needsInfo => true,
      _ => false,
    };

String _roleLabel(OrganizationRole role) => switch (role) {
  OrganizationRole.owner => 'Owner',
  OrganizationRole.manager => 'Manager',
  OrganizationRole.finance => 'Finance',
  OrganizationRole.door => 'Door',
};

String _applicationStatusLabel(OrganizationApplicationStatus status) =>
    switch (status) {
      OrganizationApplicationStatus.draft => 'Draft',
      OrganizationApplicationStatus.submitted => 'Submitted',
      OrganizationApplicationStatus.underReview => 'Under review',
      OrganizationApplicationStatus.needsInfo => 'Needs info',
      OrganizationApplicationStatus.approved => 'Approved',
      OrganizationApplicationStatus.rejected => 'Rejected',
      OrganizationApplicationStatus.withdrawn => 'Withdrawn',
    };

void showSwitcherSheet(BuildContext context) {
  final app = context.read<AppState>();
  final bandIds = app.authed ? app.myBands : const <String>[];
  showEpSheet(context, (ctx) {
    final profileName = app.profile?.name.trim();
    final displayName = profileName == null || profileName.isEmpty
        ? 'You'
        : profileName;
    final identity = app.identity;
    return EpSheetShell(
      padding: const EdgeInsets.all(20),
      maxHeightFactor: .88,
      scrollable: true,
      mainAxisSize: MainAxisSize.min,
      header: Text(
        'Switch identity'.toUpperCase(),
        semanticsLabel: 'Switch identity',
        style: Theme.of(ctx).textTheme.epSection,
      ),
      children: [
        if (app.authed)
          _IdentityOption(
            name: displayName,
            avatarName: profileName,
            caption: 'Personal account',
            active: identity is PersonalIdentity,
            onTap: () {
              Navigator.pop(ctx);
              app.toFanView();
            },
          ),
        for (final id in bandIds)
          if (app.band(id) case final Band band)
            _IdentityOption(
              name: band.name,
              avatarName: band.name,
              caption: 'Manage band · ${app.roleFor(id)}',
              active: identity is BandIdentity && identity.bandId == id,
              onTap: () {
                Navigator.pop(ctx);
                app.switchToBand(id);
              },
            ),
        if (app.authed)
          for (final membership in app.myOrganizations)
            _IdentityOption(
              key: Key('switcher-org-${membership.organization.id}'),
              name: membership.organization.name,
              avatarName: membership.organization.name,
              caption:
                  membership.organization.orgType ==
                      OrganizationType.privateHost
                  ? 'Host'
                  : 'Organizer · ${_roleLabel(membership.role)}',
              active:
                  identity is OrganizerIdentity &&
                  identity.organizationId == membership.organization.id,
              onTap: () {
                Navigator.pop(ctx);
                app.switchToOrganization(membership.organization.id);
              },
            ),
        _SwitcherAction(
          onTap: () {
            Navigator.pop(ctx);
            app.requestStartBand();
          },
          icon: Icons.add,
          label: bandIds.isEmpty ? 'START A BAND' : 'START ANOTHER BAND',
        ),
        // In-progress applications stay accessible even for existing members.
        if (_applicationInProgress(_organizerApplication(app)) ||
            (!app.myOrganizations.any(
                  (membership) =>
                      membership.organization.orgType !=
                      OrganizationType.privateHost,
                ) &&
                _organizerApplication(app)?.status !=
                    OrganizationApplicationStatus.approved))
          _SwitcherAction(
            key: const Key('switcher-become-organizer'),
            onTap: () {
              Navigator.pop(ctx);
              final application = _organizerApplication(app);
              if (application == null ||
                  application.editable ||
                  application.status ==
                      OrganizationApplicationStatus.withdrawn) {
                app.openOrganizerApply();
              } else {
                app.go(Screen.orgApplicationStatus);
              }
            },
            icon: Icons.storefront_outlined,
            label: switch (_organizerApplication(app)) {
              OrganizationApplication(
                status: OrganizationApplicationStatus.draft,
              ) =>
                'CONTINUE ORGANIZER APPLICATION',
              OrganizationApplication(status: final status)
                  when status != OrganizationApplicationStatus.withdrawn =>
                'ORGANIZER APPLICATION · ${_applicationStatusLabel(status).toUpperCase()}',
              _ => 'BECOME AN ORGANIZER',
            },
          ),
        if (_applicationInProgress(_hostApplication(app)) ||
            (!app.myOrganizations.any(
                  (membership) =>
                      membership.organization.orgType ==
                      OrganizationType.privateHost,
                ) &&
                _hostApplication(app)?.status !=
                    OrganizationApplicationStatus.approved))
          _SwitcherAction(
            key: const Key('switcher-become-host'),
            onTap: () {
              Navigator.pop(ctx);
              final application = _hostApplication(app);
              if (application == null ||
                  application.editable ||
                  application.status ==
                      OrganizationApplicationStatus.withdrawn) {
                app.openHostApply();
              } else {
                app.go(Screen.orgApplicationStatus);
              }
            },
            icon: Icons.home_outlined,
            label: switch (_hostApplication(app)) {
              OrganizationApplication(
                status: OrganizationApplicationStatus.draft,
              ) =>
                'CONTINUE HOST APPLICATION',
              OrganizationApplication(status: final status)
                  when status != OrganizationApplicationStatus.withdrawn =>
                'HOST APPLICATION · ${_applicationStatusLabel(status).toUpperCase()}',
              _ => 'BECOME A HOST',
            },
          ),
        if (app.isPlatformAdmin)
          _SwitcherAction(
            key: const Key('switcher-admin'),
            onTap: () {
              Navigator.pop(ctx);
              app.switchToAdmin();
            },
            icon: Icons.admin_panel_settings_outlined,
            label: 'EARPLUG ADMIN',
          ),
      ],
    );
  });
}

class _IdentityOption extends StatelessWidget {
  const _IdentityOption({
    super.key,
    required this.name,
    required this.avatarName,
    required this.caption,
    required this.active,
    required this.onTap,
  });

  final String name;
  final String? avatarName;
  final String caption;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SheetOption(
      onTap: onTap,
      leading: Row(
        children: [
          _IdentityTile(name: avatarName, active: active),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.epSectionHeading),
                const SizedBox(height: 4),
                Text(
                  caption,
                  style: Theme.of(context).textTheme.epChipLabel.copyWith(
                    color: context.epColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityTile extends StatelessWidget {
  const _IdentityTile({required this.name, required this.active});

  final String? name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final words = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2);
    final initials = words.isEmpty
        ? '??'
        : words.map((word) => word.characters.first).join();
    final colors = context.epColors;
    return Semantics(
      image: true,
      label: name == null || name!.trim().isEmpty
          ? 'Profile avatar'
          : '${name!.trim()} avatar',
      child: ExcludeSemantics(
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(2),
          color: active ? colors.accent : colors.panel,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initials.toUpperCase(),
              semanticsLabel: initials,
              style: Theme.of(context).textTheme.epSectionHeading.copyWith(
                color: active ? colors.onAccent : colors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitcherAction extends StatelessWidget {
  const _SwitcherAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SheetOption(
      onTap: onTap,
      verticalPadding: 16,
      leading: Row(
        children: [
          Icon(icon, size: 16, color: context.epColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label.toUpperCase(),
              semanticsLabel: label,
              style: Theme.of(
                context,
              ).textTheme.epChipLabel.copyWith(color: context.epColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ QR ticket ============================

Future<void> showQrDialog(BuildContext context, Gig gig, Venue venue) async {
  if (gig.tix != Ticketing.rsvp) return;
  late final RsvpTicket ticket;
  try {
    ticket = await context.read<AppState>().repository.ticketForGig(gig.id);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your RSVP ticket is unavailable. Refresh and try again.',
          ),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .72),
    builder: (ctx) {
      return Dialog(
        backgroundColor: ctx.epColors.ink,
        insetPadding: const EdgeInsets.all(30),
        shape: const RoundedRectangleBorder(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your ticket'.toUpperCase(),
                semanticsLabel: 'Your ticket',
                textAlign: TextAlign.center,
                style: Theme.of(
                  ctx,
                ).textTheme.epSection.copyWith(color: ctx.epColors.background),
              ),
              const SizedBox(height: 8),
              Text(
                gig.title.toUpperCase(),
                semanticsLabel: gig.title,
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.epSheetTitle.copyWith(
                  color: ctx.epColors.background,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(
                  data: ticket.payload,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ticket.checkedInAt == null
                    ? '${gig.dateShort} · ${venue.name}\nFlash this at the door.'
                    : '${gig.dateShort} · ${venue.name}\nCHECKED IN ✓',
                textAlign: TextAlign.center,
                style: Theme.of(
                  ctx,
                ).textTheme.epCaption.copyWith(color: ctx.epColors.background),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: ctx.epColors.background,
                  foregroundColor: ctx.epColors.ink,
                  shape: const StadiumBorder(),
                ),
                child: Text('Close'.toUpperCase(), semanticsLabel: 'Close'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
