import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_sheet.dart';

class _SheetShell extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SheetShell({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        decoration: const BoxDecoration(
          color: Ep.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Ep.border)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Ep.contentDisabled,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.epSectionHeading,
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final Widget leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onTap;

  const _SheetOption({
    required this.leading,
    this.trailing,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: EpCard(
        variant: selected ? EpCardVariant.selected : EpCardVariant.standard,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(child: leading),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

// ============================ city picker ============================

void showCitySheet(BuildContext context) {
  final app = context.read<AppState>();
  showEpSheet(context, (ctx) {
    final city = app.city;
    Widget option(String title, String sub, String value) {
      return _SheetOption(
        selected: city == value,
        onTap: () {
          Navigator.pop(ctx);
          app.setCity(value);
        },
        leading: Text(title, style: Theme.of(ctx).textTheme.epLabel),
        trailing: Text(sub, style: Theme.of(ctx).textTheme.epCaption),
      );
    }

    return _SheetShell(
      title: 'Where are you?',
      children: [
        const SizedBox(height: 6),
        Text(
          "Pick a scene. Everything's within BART distance anyway.",
          style: Theme.of(
            ctx,
          ).textTheme.epBody.copyWith(color: Ep.contentSecondary),
        ),
        option('San Francisco', 'Mission & around', 'sf'),
        option('Oakland', 'Temescal & around', 'oak'),
      ],
    );
  });
}

// ============================ view switcher ============================

String bandEntryLabel(int bandCount) => switch (bandCount) {
  0 => 'Start a band',
  1 => 'Manage band',
  _ => 'Switch band',
};

void showSwitcherSheet(BuildContext context) {
  final app = context.read<AppState>();
  showEpSheet(context, (ctx) {
    final profileName = app.profile?.name.trim();
    final displayName = profileName == null || profileName.isEmpty
        ? 'You'
        : profileName;
    return _SheetShell(
      title: bandEntryLabel(app.myBands.length),
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
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              app.startBandCreate();
            },
            icon: const Icon(Icons.add),
            label: Text(
              app.myBands.isEmpty ? 'START A BAND' : 'START ANOTHER BAND',
            ),
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
        backgroundColor: Ep.contentPrimary,
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
                style: epDisplay(size: 14, color: Ep.background, height: 1.2),
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
                  eyeStyle: const QrEyeStyle(color: Ep.background),
                  dataModuleStyle: const QrDataModuleStyle(
                    color: Ep.background,
                  ),
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
                ).textTheme.epCaption.copyWith(color: Ep.surface),
              ),
            ],
          ),
        ),
      );
    },
  );
}
