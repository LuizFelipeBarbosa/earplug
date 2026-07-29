import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

Future<void> _showEpSheet(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .6),
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: builder,
  );
}

class _SheetShell extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SheetShell({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 44),
      decoration: BoxDecoration(
        color: Ep.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Ep.whiteA(.14))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Ep.whiteA(.25),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(title.toUpperCase(), style: epDisplay(size: 15)),
          ...children,
        ],
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? Ep.blue.withValues(alpha: .16) : Ep.bg,
          border: selected
              ? Border.all(color: Ep.blue, width: 1.5)
              : Border.all(color: Ep.whiteA(.14)),
          borderRadius: BorderRadius.circular(12),
        ),
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
  _showEpSheet(context, (ctx) {
    final city = app.city;
    Widget option(String title, String sub, String value) {
      return _SheetOption(
        selected: city == value,
        onTap: () {
          Navigator.pop(ctx);
          app.setCity(value);
        },
        leading: Text(title, style: epText(size: 13, weight: FontWeight.w800)),
        trailing: Text(sub,
            style: epText(
                size: 10.5, weight: FontWeight.w800, color: Ep.inkA(.45))),
      );
    }

    return _SheetShell(
      title: 'Where are you?',
      children: [
        const SizedBox(height: 6),
        Text("Pick a scene — everything's within BART distance anyway.",
            style: epText(size: 11.5, color: Ep.inkA(.5), height: 1.45)),
        option('San Francisco', 'Mission & around', 'sf'),
        option('Oakland', 'Temescal & around', 'oak'),
      ],
    );
  });
}

// ============================ view switcher ============================

void showSwitcherSheet(BuildContext context) {
  final app = context.read<AppState>();
  _showEpSheet(context, (ctx) {
    final profileName = app.profile?.name.trim();
    final displayName =
        profileName == null || profileName.isEmpty ? 'You' : profileName;
    return _SheetShell(
      title: 'Switch view',
      children: [
        _SheetOption(
          onTap: () {
            Navigator.pop(ctx);
            app.toFanView();
          },
          leading: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Ep.blue, shape: BoxShape.circle),
                child: Text(profileInitials(profileName),
                    style: epDisplay(size: 12, color: Colors.white)),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName, style: epText(size: 13, weight: FontWeight.w800)),
                  Text('Fan view', style: epText(size: 10.5, color: Ep.inkA(.5))),
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
                        Text(band.name.toUpperCase(),
                            style: epText(size: 13, weight: FontWeight.w800)),
                        Text('Band view · admin',
                            style: epText(size: 10.5, color: Ep.inkA(.5))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              app.startBandCreate();
            },
            child: DashedBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Text('+ START A BAND',
                  style: epText(
                      size: 13, weight: FontWeight.w900, letterSpacing: .4, color: Ep.link)),
            ),
          ),
        ),
      ],
    );
  });
}

// ============================ QR ticket ============================

/// Deterministic fake QR pattern, ported from the design spec.
List<List<bool>> qrCellsFor(String seedStr) {
  var seed = 7;
  for (final ch in seedStr.codeUnits) {
    seed = (seed * 31 + ch) % 9973;
  }
  double rnd() {
    seed = (seed * 1103515245 + 12345) % 2147483647;
    return seed / 2147483647;
  }

  const n = 17;
  bool finderCell(int r, int c, int r0, int c0) {
    final y = r - r0, x = c - c0;
    final ring = (y - 3).abs() > (x - 3).abs() ? (y - 3).abs() : (x - 3).abs();
    return ring != 2;
  }

  return List.generate(n, (r) {
    return List.generate(n, (c) {
      if (r < 7 && c < 7) return finderCell(r, c, 0, 0);
      if (r < 7 && c >= n - 7) return finderCell(r, c, 0, n - 7);
      if (r >= n - 7 && c < 7) return finderCell(r, c, n - 7, 0);
      return rnd() > 0.52;
    });
  });
}

class _QrPainter extends CustomPainter {
  final List<List<bool>> cells;

  const _QrPainter(this.cells);

  @override
  void paint(Canvas canvas, Size size) {
    final n = cells.length;
    final cell = size.width / n;
    final paint = Paint()..color = Ep.bg;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (cells[r][c]) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell + .5, cell + .5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.cells != cells;
}

void showQrDialog(BuildContext context, Gig gig, Venue venue) {
  final userKey = context.read<AppState>().profile?.email ?? 'guest';
  showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Ep.ink,
        insetPadding: const EdgeInsets.all(30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(gig.title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: epDisplay(size: 14, color: Ep.bg, height: 1.2)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.white,
                child: CustomPaint(
                  size: const Size(119, 119),
                  painter: _QrPainter(qrCellsFor('${gig.id}$userKey')),
                ),
              ),
              const SizedBox(height: 12),
              Text('${gig.dateShort} · ${venue.name}\nFlash this at the door.',
                  textAlign: TextAlign.center,
                  style: epText(
                      size: 11,
                      weight: FontWeight.w700,
                      color: Ep.bg.withValues(alpha: .6),
                      height: 1.4)),
            ],
          ),
        ),
      );
    },
  );
}
