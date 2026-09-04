import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_sheet.dart';

/// Shared visual chrome for bottom sheets presented by [showEpSheet].
class EpSheetShell extends StatelessWidget {
  const EpSheetShell({
    super.key,
    required this.padding,
    this.backgroundColor,
    this.borderColor,
    this.topRadius = 20,
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

  /// Colors fall back to the raised-surface sheet look; [EpActionSheet] and
  /// the band media sheet pass their own denser palette.
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
            decoration: BoxDecoration(
              color: handleColor ?? colors.contentDisabled,
              borderRadius: BorderRadius.circular(99),
            ),
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
          color: backgroundColor ?? colors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
          border: Border(top: BorderSide(color: borderColor ?? colors.border)),
        ),
        child: scrollable ? SingleChildScrollView(child: content) : content,
      ),
    );
  }
}

/// Keyboard-aware chrome for a form sheet: an uppercase title with a Close
/// button (or [trailing]) above [child]. Unlike [EpSheetShell] it has no drag
/// handle and rises with the on-screen keyboard.
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
        color: context.epColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(title.toUpperCase(), style: epDisplay(size: 15)),
                ),
                trailing ??
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close),
                    ),
              ],
            ),
          ),
          if (padBody)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: child,
            )
          else
            Flexible(child: child),
        ],
      ),
    );
  }
}

/// Full-width option row for a form sheet: a title over a caption, selected
/// state drawn by the card.
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
    return EpCard(
      variant: selected ? EpCardVariant.selected : EpCardVariant.standard,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleCaps ? title.toUpperCase() : title,
            style: epText(size: 12.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: epText(size: 11, color: context.epColors.contentSecondary),
          ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final Widget leading;
  final VoidCallback onTap;

  const _SheetOption({super.key, required this.leading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: EpCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [Expanded(child: leading)]),
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
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      backgroundColor: context.epColors.raised,
      borderColor: context.epColors.border,
      topRadius: 16,
      handleColor: context.epColors.mute,
      handleBottomSpacing: 14,
      mainAxisSize: MainAxisSize.min,
      header: Text(
        header.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.epSection.copyWith(
          color: context.epColors.mute,
          fontSize: 11,
        ),
      ),
      children: [
        const SizedBox(height: 8),
        for (var index = 0; index < items.length; index++) ...[
          if (index == firstDestructive) Divider(height: 17),
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
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 19, color: color),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(color: color),
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

String bandEntryLabel(int bandCount) => switch (bandCount) {
  0 => 'Start a band',
  1 => 'Manage band',
  _ => 'Switch band',
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
  showEpSheet(context, (ctx) {
    final profileName = app.profile?.name.trim();
    final displayName = profileName == null || profileName.isEmpty
        ? 'You'
        : profileName;
    return EpSheetShell(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      maxHeightFactor: .88,
      scrollable: true,
      mainAxisSize: MainAxisSize.min,
      header: Text(
        bandEntryLabel(app.myBands.length).toUpperCase(),
        style: Theme.of(ctx).textTheme.epSectionHeading,
      ),
      children: [
        _SheetOption(
          onTap: () {
            Navigator.pop(ctx);
            app.toFanView();
          },
          leading: Row(
            children: [
              EpFanAvatar(
                name: profileName,
                imageUrl: app.profile?.avatarUrl,
                size: 34,
                radius: 9,
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: Theme.of(ctx).textTheme.epLabel),
                  Text(
                    'Personal account',
                    style: Theme.of(ctx).textTheme.epCaption,
                  ),
                ],
              ),
            ],
          ),
        ),
        for (final id in app.myBands)
          if (app.band(id) case final Band band)
            _SheetOption(
              onTap: () {
                Navigator.pop(ctx);
                app.switchToBand(id);
              },
              leading: Row(
                children: [
                  BandAvatar(band, size: 34, radius: 8, fontSize: 12),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          band.name.toUpperCase(),
                          style: Theme.of(ctx).textTheme.epLabel,
                        ),
                        Text(
                          'Manage band · ${app.roleFor(id)}',
                          style: Theme.of(ctx).textTheme.epCaption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        for (final membership in app.myOrganizations)
          _SheetOption(
            key: Key('switcher-org-${membership.organization.id}'),
            onTap: () {
              Navigator.pop(ctx);
              app.switchToOrganization(membership.organization.id);
            },
            leading: Row(
              children: [
                EpFanAvatar(
                  name: membership.organization.name,
                  imageUrl: membership.organization.photoUrls.isEmpty
                      ? null
                      : membership.organization.photoUrls.first,
                  size: 34,
                  radius: 8,
                  fontSize: 12,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        membership.organization.name.toUpperCase(),
                        style: Theme.of(ctx).textTheme.epLabel,
                      ),
                      Text(
                        'Organizer · ${_roleLabel(membership.role)}',
                        style: Theme.of(ctx).textTheme.epCaption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              app.startBandCreate();
            },
            icon: Icon(Icons.add),
            label: Text(
              app.myBands.isEmpty ? 'START A BAND' : 'START ANOTHER BAND',
            ),
          ),
        ),
        // Approved organizers enter through their membership; withdrawn
        // applications may start over.
        if (app.myOrganizationApplication?.status !=
            OrganizationApplicationStatus.approved)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              key: const Key('switcher-become-organizer'),
              onPressed: () {
                Navigator.pop(ctx);
                final application = app.myOrganizationApplication;
                if (application == null ||
                    application.editable ||
                    application.status ==
                        OrganizationApplicationStatus.withdrawn) {
                  app.openOrganizerApply();
                } else {
                  app.go(Screen.orgApplicationStatus);
                }
              },
              icon: const Icon(Icons.storefront_outlined),
              label: Text(switch (app.myOrganizationApplication) {
                OrganizationApplication(
                  status: OrganizationApplicationStatus.draft,
                ) =>
                  'CONTINUE ORGANIZER APPLICATION',
                OrganizationApplication(status: final status)
                    when status != OrganizationApplicationStatus.withdrawn =>
                  'ORGANIZER APPLICATION · ${_applicationStatusLabel(status).toUpperCase()}',
                _ => 'BECOME AN ORGANIZER',
              }),
            ),
          ),
        if (app.isPlatformAdmin)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              key: const Key('switcher-admin'),
              onPressed: () {
                Navigator.pop(ctx);
                app.switchToAdmin();
              },
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('EARPLUG ADMIN'),
            ),
          ),
      ],
    );
  });
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
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (ctx) {
      return Dialog(
        backgroundColor: context.epColors.contentPrimary,
        insetPadding: const EdgeInsets.all(30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                gig.title.toUpperCase(),
                textAlign: TextAlign.center,
                style: epDisplay(
                  size: 14,
                  color: context.epColors.background,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
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
                  context,
                ).textTheme.epCaption.copyWith(color: context.epColors.surface),
              ),
            ],
          ),
        ),
      );
    },
  );
}
