import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Display data already known by the screen that launches Door Mode.
///
/// Door Mode receives this presentation value instead of trying to reconstruct
/// gig details from the door-roster response, which only contains counts.
class DoorModeLaunch {
  const DoorModeLaunch({
    required this.projectId,
    required this.gigTitle,
    required this.venueName,
    required this.doorsTime,
  });

  final String projectId;
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
  final List<DoorCheckInResult> _recentCheckIns = [];

  DoorRoster? _roster;
  DoorCheckInResult? _result;
  String? _rosterFailureMessage;
  String? _checkInFailureMessage;
  bool _checking = false;
  bool _scannerOpen = false;
  bool _scannerLocked = false;
  Timer? _scannerUnlockTimer;

  @override
  void initState() {
    super.initState();
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
      final roster = await context.read<AppState>().repository.doorRoster(
        widget.launch.projectId,
      );
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
      final result = await context.read<AppState>().repository.checkInTicket(
        projectId: widget.launch.projectId,
        payload: code,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _manualCode.clear();
        if (result.status == DoorCheckInStatus.checkedIn) {
          _recentCheckIns.insert(0, result);
          if (_recentCheckIns.length > _recentLimit) {
            _recentCheckIns.removeRange(_recentLimit, _recentCheckIns.length);
          }
        }
      });
      _announce(_resultMessage(result));
      await _refreshRoster(
        checkInSucceeded: result.status == DoorCheckInStatus.checkedIn,
      );
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
        backgroundColor: Ep.dark,
        appBar: AppBar(
          backgroundColor: Ep.dark,
          leading: IconButton(
            tooltip: _scannerOpen ? 'Back to door overview' : 'Close Door Mode',
            onPressed: _scannerOpen
                ? _closeScanner
                : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
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
                      'The scan could not be read. Hold the ticket steady or enter it below.',
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
  final DoorRoster? roster;
  final List<DoorCheckInResult> recentCheckIns;
  final String? rosterFailure;
  final VoidCallback onOpenScanner;
  final VoidCallback onEnterCode;
  final VoidCallback onRetryRoster;

  @override
  Widget build(BuildContext context) {
    final denominator = roster == null
        ? '…'
        : roster!.truncated
        ? '${roster!.total} loaded'
        : '${roster!.total}';
    final progress = roster == null || roster!.total == 0
        ? 0.0
        : (roster!.checkedIn / roster!.total).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        Text(
          'DOOR MODE · ${launch.venueName.toUpperCase()}',
          style: Theme.of(
            context,
          ).textTheme.epSection.copyWith(color: Ep.volt, fontSize: 11),
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
        Text(
          'CHECKED IN',
          style: Theme.of(context).textTheme.epSection.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: roster == null
              ? 'Checked-in count loading'
              : roster!.truncated
              ? '${roster!.checkedIn} checked in from ${roster!.total} loaded roster entries. Roster is limited.'
              : '${roster!.checkedIn} of ${roster!.total} checked in',
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${roster?.checkedIn ?? '…'}',
                  style: Theme.of(
                    context,
                  ).textTheme.epDisplay.copyWith(fontSize: 54, color: Ep.volt),
                ),
                TextSpan(
                  text: ' / $denominator',
                  style: Theme.of(context).textTheme.epDisplay.copyWith(
                    fontSize: roster?.truncated == true ? 17 : 28,
                    color: Ep.mute,
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
            ).textTheme.epCaption.copyWith(color: Ep.volt),
          ),
        ],
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: progress,
            backgroundColor: Ep.raised,
            color: Ep.volt,
          ),
        ),
        if (rosterFailure != null && roster == null) ...[
          const SizedBox(height: 12),
          Text(
            rosterFailure!,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.epCaption.copyWith(color: Ep.destructive),
          ),
          TextButton(
            onPressed: onRetryRoster,
            child: const Text('RETRY ROSTER'),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('door-open-scanner'),
          onPressed: onOpenScanner,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('OPEN SCANNER'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const Key('door-enter-code'),
          onPressed: onEnterCode,
          child: const Text('ENTER TICKET CODE'),
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
              leading: const Icon(Icons.check, size: 18, color: Ep.success),
              title: result.fanName ?? 'Fan',
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
  final DoorRoster? roster;
  final DoorCheckInResult? result;
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
                    'CAMERA UNAVAILABLE\n\nAllow camera access, try another device, or enter the ticket below.',
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
        if (result?.status == DoorCheckInStatus.checkedIn &&
            rosterFailure != null) ...[
          const SizedBox(height: 8),
          const _RosterRefreshFailureNotice(),
        ],
        const SizedBox(height: 18),
        const SectionBar(label: 'MANUAL FALLBACK'),
        const SizedBox(height: 8),
        TextField(
          key: const Key('door-manual-ticket'),
          controller: manualCode,
          focusNode: manualFocus,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Ticket code',
            hintText: 'e.g. EP-9F2K-41',
          ),
          onSubmitted: (_) => onManualCheck(),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: checking ? null : onManualCheck,
          child: Text(checking ? 'CHECKING…' : 'CHECK TICKET'),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: Theme.of(context).textTheme.epCaption,
            children: const [
              TextSpan(
                text: '✓ checked in',
                style: TextStyle(color: Ep.success),
              ),
              TextSpan(text: ' · '),
              TextSpan(
                text: 'already checked in / wrong gig',
                style: TextStyle(color: Ep.volt),
              ),
              TextSpan(text: ' · '),
              TextSpan(
                text: 'invalid or revoked',
                style: TextStyle(color: Ep.destructive),
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
          ColoredBox(color: Ep.surface, child: child),
          const IgnorePointer(child: CustomPaint(painter: _ScannerPainter())),
          const Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: Text(
              "POINT AT A FAN'S QR — NO BUTTON NEEDED",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Ep.contentSecondary,
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
  const _ScannerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Ep.volt
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Ep.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_camera, size: 46, color: Ep.mute),
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

  final DoorCheckInResult result;
  final DoorRoster? roster;

  @override
  Widget build(BuildContext context) {
    final tone = _resultTone(result.status);
    final message = _resultMessage(result);
    final count = result.status == DoorCheckInStatus.checkedIn && roster != null
        ? roster!.truncated
              ? ' · ${roster!.checkedIn} checked in (${roster!.total} loaded)'
              : ' · ${roster!.checkedIn} of ${roster!.total}'
        : '';
    return Semantics(
      key: const Key('door-result'),
      container: true,
      liveRegion: true,
      label: '$message$count',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.background,
          border: Border.all(color: tone.foreground),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$message$count',
          style: Theme.of(
            context,
          ).textTheme.epLabel.copyWith(color: tone.foreground),
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
          color: Ep.destructiveTint,
          border: Border.all(color: Ep.destructive),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.epLabel.copyWith(color: Ep.destructive),
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
          color: Ep.warningTint,
          border: Border.all(color: Ep.volt),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'CHECK-IN RECORDED · COUNT COULD NOT REFRESH · DO NOT SCAN AGAIN',
          style: Theme.of(context).textTheme.epLabel.copyWith(color: Ep.volt),
        ),
      ),
    );
  }
}

({Color foreground, Color background}) _resultTone(DoorCheckInStatus status) {
  return switch (status) {
    DoorCheckInStatus.checkedIn => (
      foreground: Ep.success,
      background: Ep.successTint,
    ),
    DoorCheckInStatus.alreadyCheckedIn || DoorCheckInStatus.wrongGig => (
      foreground: Ep.volt,
      background: Ep.warningTint,
    ),
    DoorCheckInStatus.invalid => (
      foreground: Ep.destructive,
      background: Ep.destructiveTint,
    ),
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
  if (checkedInAt == null) return 'just now';
  return TimeOfDay.fromDateTime(checkedInAt.toLocal()).format(context);
}
