import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

/// Display data already known by the screen that launches Door Mode.
///
/// Door Mode receives this presentation value instead of trying to reconstruct
/// gig details from the door-roster response, which only contains counts.
class DoorModeLaunch {
  const DoorModeLaunch({
    this.projectId,
    this.gigId,
    required this.gigTitle,
    required this.venueName,
    required this.doorsTime,
  }) : assert(
         (projectId == null) != (gigId == null),
         'exactly one of projectId or gigId must be set',
       );

  const DoorModeLaunch.organizer({
    required String gigId,
    required String gigTitle,
    required String venueName,
    required String doorsTime,
  }) : this(
         gigId: gigId,
         gigTitle: gigTitle,
         venueName: venueName,
         doorsTime: doorsTime,
       );

  final String? projectId;
  final String? gigId;
  final String gigTitle;
  final String venueName;
  final String doorsTime;
}

Future<void> showDoorMode(BuildContext context, DoorModeLaunch launch) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DoorModeScreen(launch: launch),
      ),
    );

Future<void> showOrganizerDoorMode(
  BuildContext context, {
  required String gigId,
  required String gigTitle,
  required String venueName,
  required String doorsTime,
}) => showDoorMode(
  context,
  DoorModeLaunch.organizer(
    gigId: gigId,
    gigTitle: gigTitle,
    venueName: venueName,
    doorsTime: doorsTime,
  ),
);

enum _DoorTone {
  success,
  warning,
  failure;

  ({Color foreground, Color background}) colors(BuildContext context) =>
      switch (this) {
        success => (
          foreground: context.epColors.success,
          background: context.epColors.successTint,
        ),
        warning => (
          foreground: context.epColors.volt,
          background: context.epColors.warningTint,
        ),
        failure => (
          foreground: context.epColors.destructive,
          background: context.epColors.destructiveTint,
        ),
      };
}

class _DoorOutcome {
  const _DoorOutcome({
    required this.tone,
    required this.headline,
    this.detail,
    this.checkedInAt,
    this.holderName,
  });

  final _DoorTone tone;
  final String headline;
  final String? detail;
  final DateTime? checkedInAt;
  final String? holderName;
}

class _DoorCounts {
  const _DoorCounts({
    this.primaryLabel,
    required this.primaryCount,
    required this.primaryCheckedIn,
    this.secondaryLabel,
    this.secondaryCount,
    this.secondaryCheckedIn,
    required this.truncated,
  });

  final String? primaryLabel;
  final int primaryCount;
  final int primaryCheckedIn;
  final String? secondaryLabel;
  final int? secondaryCount;
  final int? secondaryCheckedIn;
  final bool truncated;
}

sealed class _DoorBackend {
  Future<_DoorCounts> roster();
  Future<_DoorOutcome> checkIn(String payload);
}

class _BandDoorBackend extends _DoorBackend {
  _BandDoorBackend(this._repository, this._projectId);

  final EarplugRepository _repository;
  final String _projectId;

  @override
  Future<_DoorCounts> roster() async {
    final counts = await _repository.doorRoster(_projectId);
    return _DoorCounts(
      primaryCount: counts.total,
      primaryCheckedIn: counts.checkedIn,
      truncated: counts.truncated,
    );
  }

  @override
  Future<_DoorOutcome> checkIn(String payload) async {
    final result = await _repository.checkInTicket(
      projectId: _projectId,
      payload: payload,
    );
    return _DoorOutcome(
      tone: _resultTone(result.status),
      headline: _resultMessage(result),
      holderName: result.fanName ?? 'Fan',
      checkedInAt: result.checkedInAt,
    );
  }
}

class _OrganizerDoorBackend extends _DoorBackend {
  _OrganizerDoorBackend(
    this._app,
    this._gigId, {
    required this._formatCheckInTime,
  });

  final AppState _app;
  final String _gigId;
  final String Function(DateTime?) _formatCheckInTime;

  @override
  Future<_DoorCounts> roster() async {
    final counts = await _app.organizerDoorRoster(_gigId);
    return _DoorCounts(
      primaryLabel: 'RSVPs',
      primaryCount: counts.rsvpTotal,
      primaryCheckedIn: counts.rsvpCheckedIn,
      secondaryLabel: 'Tickets',
      secondaryCount: counts.ticketsSold,
      secondaryCheckedIn: counts.ticketsCheckedIn,
      truncated: counts.truncated,
    );
  }

  @override
  Future<_DoorOutcome> checkIn(String payload) async {
    final result = await _app.organizerCheckIn(_gigId, payload);
    final (tone, headline) = switch (result.kind) {
      TicketDoorKind.checkedIn => (
        _DoorTone.success,
        '${result.holderName ?? 'Fan'} checked in ✓',
      ),
      TicketDoorKind.alreadyUsed => (
        _DoorTone.warning,
        'Already checked in ${_formatCheckInTime(result.checkedInAt)}',
      ),
      TicketDoorKind.refunded => (
        _DoorTone.failure,
        'Ticket refunded — not valid',
      ),
      TicketDoorKind.eventCancelled => (_DoorTone.failure, 'Event cancelled'),
      TicketDoorKind.wrongEvent => (
        _DoorTone.warning,
        'Ticket is for another event',
      ),
      TicketDoorKind.unknown => (_DoorTone.failure, 'Not a valid ticket'),
    };
    return _DoorOutcome(
      tone: tone,
      headline: headline,
      detail: result.kind == TicketDoorKind.checkedIn
          ? switch (result.source) {
              'ticket' => 'Ticket',
              'rsvp' => 'RSVP',
              _ => null,
            }
          : null,
      checkedInAt: result.checkedInAt,
      holderName: result.holderName ?? 'Fan',
    );
  }
}

class DoorModeScreen extends StatefulWidget {
  const DoorModeScreen({super.key, required this.launch});

  final DoorModeLaunch launch;

  @override
  State<DoorModeScreen> createState() => _DoorModeScreenState();
}

class _DoorModeScreenState extends State<DoorModeScreen> {
  static const _recentLimit = 8;

  final _manualCode = TextEditingController();
  final _manualFocus = FocusNode();
  final _scannerController = MobileScannerController();
  final List<_DoorOutcome> _recentCheckIns = [];
  late final _DoorBackend _backend;

  _DoorCounts? _roster;
  _DoorOutcome? _result;
  String? _rosterFailureMessage;
  String? _checkInFailureMessage;
  bool _checking = false;
  bool _scannerOpen = false;
  bool _scannerLocked = false;
  Timer? _scannerUnlockTimer;

  @override
  void initState() {
    super.initState();
    final context = this.context;
    final app = context.read<AppState>();
    final projectId = widget.launch.projectId;
    _backend = projectId != null
        ? _BandDoorBackend(app.repository, projectId)
        : _OrganizerDoorBackend(
            app,
            widget.launch.gigId!,
            formatCheckInTime: (time) => _checkInTime(context, time),
          );
    _refreshRoster();
  }

  @override
  void dispose() {
    _scannerUnlockTimer?.cancel();
    unawaited(_scannerController.dispose());
    _manualFocus.dispose();
    _manualCode.dispose();
    super.dispose();
  }

  Future<void> _refreshRoster({bool checkInSucceeded = false}) async {
    try {
      final roster = await _backend.roster();
      if (!mounted) return;
      setState(() {
        _roster = roster;
        _rosterFailureMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      const message =
          'Door roster is unavailable. Check your admin access and connection.';
      setState(() => _rosterFailureMessage = message);
      _announce(
        checkInSucceeded
            ? 'Check-in succeeded, but the roster count could not refresh. Do not scan this ticket again.'
            : message,
        assertive: true,
      );
    }
  }

  Future<void> _checkIn(String payload, {bool fromScanner = false}) async {
    final code = payload.trim();
    if (_checking || code.isEmpty || (fromScanner && _scannerLocked)) return;

    _scannerUnlockTimer?.cancel();
    setState(() {
      _checking = true;
      _scannerLocked = fromScanner;
      _checkInFailureMessage = null;
    });
    try {
      final result = await _backend.checkIn(code);
      if (!mounted) return;
      setState(() {
        _result = result;
        _manualCode.clear();
        if (result.tone == _DoorTone.success) {
          _recentCheckIns.insert(0, result);
          if (_recentCheckIns.length > _recentLimit) {
            _recentCheckIns.removeRange(_recentLimit, _recentCheckIns.length);
          }
        }
      });
      _announce(result.headline);
      await _refreshRoster(checkInSucceeded: result.tone == _DoorTone.success);
    } catch (_) {
      if (mounted) {
        _showCheckInFailure(
          'Check-in failed. Keep the fan at the door and retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        if (fromScanner) {
          _scannerUnlockTimer = Timer(const Duration(milliseconds: 1400), () {
            if (mounted) setState(() => _scannerLocked = false);
          });
        }
      }
    }
  }

  void _showCheckInFailure(String message) {
    setState(() {
      _checkInFailureMessage = message;
      _result = null;
    });
    _announce(message, assertive: true);
  }

  void _announce(String message, {bool assertive = false}) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
        assertiveness: assertive
            ? Assertiveness.assertive
            : Assertiveness.polite,
      ),
    );
  }

  void _openScanner({bool focusManual = false}) {
    setState(() {
      _scannerOpen = true;
      _result = null;
      _checkInFailureMessage = null;
    });
    if (focusManual) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _manualFocus.requestFocus();
      });
    }
  }

  Future<void> _closeScanner() async {
    try {
      await _scannerController.stop();
    } catch (_) {
      // Removing the scanner subtree still disposes its preview. Door staff
      // must always be able to return to the overview after a camera failure.
    }
    if (!mounted) return;
    setState(() {
      _scannerOpen = false;
      _scannerLocked = false;
      _result = null;
      _checkInFailureMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_scannerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeScanner());
      },
      child: Scaffold(
        backgroundColor: context.epColors.dark,
        appBar: AppBar(
          backgroundColor: context.epColors.dark,
          leading: CircleIconButton(
            tooltip: _scannerOpen ? 'Back to door overview' : 'Close Door Mode',
            onTap: _scannerOpen
                ? _closeScanner
                : () => Navigator.of(context).pop(),
            icon: Icons.arrow_back,
          ),
          title: Text(_scannerOpen ? 'SCAN TICKET' : 'DOOR MODE'),
        ),
        body: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _scannerOpen
                ? _ScannerView(
                    key: const Key('door-scanner-view'),
                    controller: _scannerController,
                    manualCode: _manualCode,
                    manualFocus: _manualFocus,
                    roster: _roster,
                    result: _result,
                    rosterFailure: _rosterFailureMessage,
                    checkInFailure: _checkInFailureMessage,
                    checking: _checking,
                    scannerLocked: _scannerLocked,
                    onDetect: (value) => _checkIn(value, fromScanner: true),
                    onDetectError: () => _showCheckInFailure(
                      'The scan could not be read. Hold the ticket steady or enter it above.',
                    ),
                    onManualCheck: () => _checkIn(_manualCode.text),
                  )
                : _Viewer(
                    key: const Key('door-viewer'),
                    launch: widget.launch,
                    roster: _roster,
                    recentCheckIns: _recentCheckIns,
                    rosterFailure: _rosterFailureMessage,
                    onOpenScanner: _openScanner,
                    onEnterCode: () => _openScanner(focusManual: true),
                    onRetryRoster: _refreshRoster,
                  ),
          ),
        ),
      ),
    );
  }
}

class _Viewer extends StatelessWidget {
  const _Viewer({
    super.key,
    required this.launch,
    required this.roster,
    required this.recentCheckIns,
    required this.rosterFailure,
    required this.onOpenScanner,
    required this.onEnterCode,
    required this.onRetryRoster,
  });

  final DoorModeLaunch launch;
  final _DoorCounts? roster;
  final List<_DoorOutcome> recentCheckIns;
  final String? rosterFailure;
  final VoidCallback onOpenScanner;
  final VoidCallback onEnterCode;
  final VoidCallback onRetryRoster;

  @override
  Widget build(BuildContext context) {
    final denominator = roster == null
        ? '…'
        : roster!.truncated
        ? '${roster!.primaryCount} loaded'
        : '${roster!.primaryCount}';
    final progress = roster == null || roster!.primaryCount == 0
        ? 0.0
        : (roster!.primaryCheckedIn / roster!.primaryCount).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        Text(
          'DOOR MODE · ${launch.venueName.toUpperCase()}',
          style: Theme.of(context).textTheme.epSection.copyWith(
            color: context.epColors.volt,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Text(launch.gigTitle, style: Theme.of(context).textTheme.epPosterTitle),
        const SizedBox(height: 8),
        Text(
          'DOORS ${launch.doorsTime.toUpperCase()}',
          style: Theme.of(context).textTheme.epMeta.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 28),
        if (roster?.secondaryLabel != null)
          Text(
            '${roster!.primaryLabel} ${roster!.primaryCheckedIn}/${roster!.primaryCount}'
            ' · ${roster!.secondaryLabel} ${roster!.secondaryCheckedIn}/${roster!.secondaryCount}'
            '${roster!.truncated ? ' · 500+' : ''}',
            key: const Key('door-organizer-roster'),
            style: Theme.of(
              context,
            ).textTheme.epLabel.copyWith(color: context.epColors.volt),
          )
        else ...[
          Text(
            'CHECKED IN',
            style: Theme.of(context).textTheme.epSection.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: roster == null
                ? 'Checked-in count loading'
                : roster!.truncated
                ? '${roster!.primaryCheckedIn} checked in from ${roster!.primaryCount} loaded roster entries. Roster is limited.'
                : '${roster!.primaryCheckedIn} of ${roster!.primaryCount} checked in',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${roster?.primaryCheckedIn ?? '…'}',
                    style: Theme.of(context).textTheme.epDisplay.copyWith(
                      fontSize: 54,
                      color: context.epColors.volt,
                    ),
                  ),
                  TextSpan(
                    text: ' / $denominator',
                    style: Theme.of(context).textTheme.epDisplay.copyWith(
                      fontSize: roster?.truncated == true ? 17 : 28,
                      color: context.epColors.mute,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (roster?.truncated == true) ...[
            const SizedBox(height: 4),
            Text(
              'LIMITED ROSTER LOADED · TOTAL ATTENDANCE MAY BE HIGHER',
              key: const Key('door-roster-limited'),
              style: Theme.of(
                context,
              ).textTheme.epCaption.copyWith(color: context.epColors.volt),
            ),
          ],
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: context.epColors.raised,
              color: context.epColors.volt,
            ),
          ),
        ],
        if (rosterFailure != null) ...[
          const SizedBox(height: 12),
          Text(
            rosterFailure!,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.epCaption.copyWith(color: context.epColors.destructive),
          ),
          if (roster != null)
            Text(
              'DISPLAYED COUNTS MAY BE STALE',
              key: const Key('door-roster-stale-failure'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.epCaption.copyWith(
                color: context.epColors.destructive,
              ),
            ),
          TextButton(onPressed: onRetryRoster, child: Text('RETRY ROSTER')),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('door-open-scanner'),
          onPressed: onOpenScanner,
          icon: Icon(Icons.qr_code_scanner),
          label: Text('OPEN SCANNER'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const Key('door-enter-code'),
          onPressed: onEnterCode,
          child: Text('ENTER TICKET CODE'),
        ),
        const SizedBox(height: 22),
        SectionBar(
          label: 'RECENT CHECK-INS',
          count: recentCheckIns.isEmpty ? null : recentCheckIns.length,
        ),
        const SizedBox(height: 8),
        if (recentCheckIns.isEmpty)
          Text(
            'Successful check-ins from this open session will appear here.',
            key: const Key('door-recent-empty'),
            style: Theme.of(context).textTheme.epCaption,
          )
        else
          for (final result in recentCheckIns)
            LedgerRow(
              leading: Icon(
                Icons.check,
                size: 18,
                color: context.epColors.success,
              ),
              title: result.holderName ?? result.headline,
              details: [_checkInTime(context, result.checkedInAt), 'door'],
            ),
      ],
    );
  }
}

class _ScannerView extends StatelessWidget {
  const _ScannerView({
    super.key,
    required this.controller,
    required this.manualCode,
    required this.manualFocus,
    required this.roster,
    required this.result,
    required this.rosterFailure,
    required this.checkInFailure,
    required this.checking,
    required this.scannerLocked,
    required this.onDetect,
    required this.onDetectError,
    required this.onManualCheck,
  });

  final MobileScannerController controller;
  final TextEditingController manualCode;
  final FocusNode manualFocus;
  final _DoorCounts? roster;
  final _DoorOutcome? result;
  final String? rosterFailure;
  final String? checkInFailure;
  final bool checking;
  final bool scannerLocked;
  final ValueChanged<String> onDetect;
  final VoidCallback onDetectError;
  final VoidCallback onManualCheck;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const SectionBar.form(label: 'Enter ticket code'),
        const SizedBox(height: 8),
        EpLabeledField(
          fieldKey: const Key('door-manual-ticket'),
          controller: manualCode,
          focusNode: manualFocus,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          label: 'Ticket code',
          hint: 'e.g. EP-9F2K-41',
          onSubmitted: (_) => onManualCheck(),
        ),
        const SizedBox(height: EpLayout.fieldGap),
        FilledButton(
          onPressed: checking ? null : onManualCheck,
          child: Text(checking ? 'CHECKING…' : 'CHECK TICKET'),
        ),
        const SizedBox(height: 20),
        SizedBox(
          key: const Key('door-scanner'),
          height: 360,
          child: _ScannerFrame(
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value != null && !scannerLocked) onDetect(value);
              },
              onDetectError: (_, _) => onDetectError(),
              placeholderBuilder: (_) =>
                  const _CameraFallback(message: 'STARTING CAMERA…'),
              errorBuilder: (_, _) => const _CameraFallback(
                message:
                    'CAMERA UNAVAILABLE\n\nAllow camera access, try another device, or enter the ticket above.',
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (result != null)
          _ResultBanner(
            result: result!,
            roster: rosterFailure == null ? roster : null,
          )
        else if (checkInFailure != null)
          _FailureBanner(message: checkInFailure!),
        if (result?.tone == _DoorTone.success && rosterFailure != null) ...[
          const SizedBox(height: 8),
          const _RosterRefreshFailureNotice(),
        ],
        const SizedBox(height: 18),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.epCaption,
            children: [
              TextSpan(
                text: '✓ checked in',
                style: TextStyle(color: context.epColors.success),
              ),
              TextSpan(text: ' · '),
              TextSpan(
                text: 'already checked in / wrong gig',
                style: TextStyle(color: context.epColors.volt),
              ),
              TextSpan(text: ' · '),
              TextSpan(
                text: 'invalid or revoked',
                style: TextStyle(color: context.epColors.destructive),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.epColors.surface, child: child),
          IgnorePointer(
            child: CustomPaint(painter: _ScannerPainter(context.epColors.volt)),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: Text(
              "POINT AT A FAN'S QR — NO BUTTON NEEDED",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.epColors.contentSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerPainter extends CustomPainter {
  const _ScannerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const inset = 24.0;
    const arm = 26.0;
    final path = Path()
      ..moveTo(inset, inset + arm)
      ..lineTo(inset, inset)
      ..lineTo(inset + arm, inset)
      ..moveTo(size.width - inset - arm, inset)
      ..lineTo(size.width - inset, inset)
      ..lineTo(size.width - inset, inset + arm)
      ..moveTo(size.width - inset, size.height - inset - arm)
      ..lineTo(size.width - inset, size.height - inset)
      ..lineTo(size.width - inset - arm, size.height - inset)
      ..moveTo(inset + arm, size.height - inset)
      ..lineTo(inset, size.height - inset)
      ..lineTo(inset, size.height - inset - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScannerPainter oldDelegate) => oldDelegate.color != color;
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.epColors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_camera, size: 46, color: context.epColors.mute),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epCaption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result, required this.roster});

  final _DoorOutcome result;
  final _DoorCounts? roster;

  @override
  Widget build(BuildContext context) {
    final tone = result.tone.colors(context);
    final message = result.headline;
    final count =
        result.tone == _DoorTone.success &&
            roster != null &&
            roster!.secondaryLabel == null
        ? roster!.truncated
              ? ' · ${roster!.primaryCheckedIn} checked in (${roster!.primaryCount} loaded)'
              : ' · ${roster!.primaryCheckedIn} of ${roster!.primaryCount}'
        : '';
    final headline = Text(
      '$message$count',
      style: Theme.of(
        context,
      ).textTheme.epLabel.copyWith(color: tone.foreground),
    );
    return Semantics(
      key: const Key('door-result'),
      container: true,
      liveRegion: true,
      label:
          '$message$count${result.detail == null ? '' : ' · ${result.detail}'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.background,
          border: Border.all(color: tone.foreground),
          borderRadius: BorderRadius.circular(10),
        ),
        child: result.detail == null
            ? headline
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  headline,
                  const SizedBox(height: 4),
                  Text(
                    result.detail!,
                    style: Theme.of(
                      context,
                    ).textTheme.epCaption.copyWith(color: tone.foreground),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('door-result'),
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.epColors.destructiveTint,
          border: Border.all(color: context.epColors.destructive),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.epLabel.copyWith(color: context.epColors.destructive),
        ),
      ),
    );
  }
}

class _RosterRefreshFailureNotice extends StatelessWidget {
  const _RosterRefreshFailureNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('door-roster-refresh-failure'),
      container: true,
      liveRegion: true,
      label:
          'Check-in recorded. Roster count could not refresh. Do not scan this ticket again.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.epColors.warningTint,
          border: Border.all(color: context.epColors.volt),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'CHECK-IN RECORDED · COUNT COULD NOT REFRESH · DO NOT SCAN AGAIN',
          style: Theme.of(
            context,
          ).textTheme.epLabel.copyWith(color: context.epColors.volt),
        ),
      ),
    );
  }
}

_DoorTone _resultTone(DoorCheckInStatus status) {
  return switch (status) {
    DoorCheckInStatus.checkedIn => _DoorTone.success,
    DoorCheckInStatus.alreadyCheckedIn ||
    DoorCheckInStatus.wrongGig => _DoorTone.warning,
    DoorCheckInStatus.invalid => _DoorTone.failure,
  };
}

String _resultMessage(DoorCheckInResult result) {
  return switch (result.status) {
    DoorCheckInStatus.checkedIn => '${result.fanName ?? 'Fan'} checked in ✓',
    DoorCheckInStatus.alreadyCheckedIn =>
      '${result.fanName ?? 'This fan'} was already checked in.',
    DoorCheckInStatus.wrongGig => 'That ticket belongs to a different gig.',
    DoorCheckInStatus.invalid => 'Invalid or revoked EarPlug ticket.',
  };
}

String _checkInTime(BuildContext context, DateTime? checkedInAt) {
  if (checkedInAt == null || !context.mounted) return 'just now';
  return TimeOfDay.fromDateTime(checkedInAt.toLocal()).format(context);
}
