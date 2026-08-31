import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> showDoorMode(BuildContext context, String projectId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _DoorModeScreen(projectId: projectId),
      ),
    );

class _DoorModeScreen extends StatefulWidget {
  const _DoorModeScreen({required this.projectId});

  final String projectId;

  @override
  State<_DoorModeScreen> createState() => _DoorModeScreenState();
}

class _DoorModeScreenState extends State<_DoorModeScreen> {
  final _manualCode = TextEditingController();
  DoorRoster? _roster;
  String? _message;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refreshRoster();
  }

  @override
  void dispose() {
    _manualCode.dispose();
    super.dispose();
  }

  Future<void> _refreshRoster() async {
    try {
      final roster = await context.read<AppState>().repository.doorRoster(
        widget.projectId,
      );
      if (mounted) setState(() => _roster = roster);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Door roster is unavailable. Check your admin access and connection.',
        );
      }
    }
  }

  Future<void> _checkIn(String payload) async {
    if (_checking || payload.trim().isEmpty) return;
    setState(() => _checking = true);
    try {
      final result = await context.read<AppState>().repository.checkInTicket(
        projectId: widget.projectId,
        payload: payload.trim(),
      );
      if (!mounted) return;
      setState(() {
        _message = switch (result.status) {
          DoorCheckInStatus.checkedIn =>
            '${result.fanName ?? 'Fan'} checked in ✓',
          DoorCheckInStatus.alreadyCheckedIn =>
            '${result.fanName ?? 'This fan'} was already checked in.',
          DoorCheckInStatus.wrongGig =>
            'That ticket belongs to a different gig.',
          DoorCheckInStatus.invalid => 'Invalid or revoked EarPlug ticket.',
        };
        _manualCode.clear();
      });
      await _refreshRoster();
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _message = 'Check-in failed. Keep the fan at the door and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    return Scaffold(
      backgroundColor: Ep.background,
      appBar: AppBar(title: const Text('DOOR MODE')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EpCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'RSVPS', value: roster?.total),
                _Stat(label: 'CHECKED IN', value: roster?.checkedIn),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            key: const Key('door-scanner'),
            height: 320,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: MobileScanner(
                onDetect: (capture) {
                  final value = capture.barcodes.firstOrNull?.rawValue;
                  if (value != null) _checkIn(value);
                },
                onDetectError: (_, _) {
                  if (mounted) {
                    setState(
                      () => _message =
                          'The scan could not be read. Hold the ticket steady or enter it below.',
                    );
                  }
                },
                errorBuilder: (_, error) => ColoredBox(
                  color: Ep.surface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'CAMERA UNAVAILABLE\n\nAllow camera access, try another device, or enter the ticket below.',
                        textAlign: TextAlign.center,
                        style: epText(color: Ep.contentSecondary, height: 1.4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('door-manual-ticket'),
            controller: _manualCode,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Ticket code fallback',
            ),
            onSubmitted: _checkIn,
          ),
          const SizedBox(height: 8),
          EpButton(
            _checking ? 'CHECKING…' : 'CHECK TICKET',
            kind: _checking ? EpButtonKind.disabled : EpButtonKind.filled,
            onTap: _checking ? null : () => _checkIn(_manualCode.text),
          ),
          if (_message case final message?) ...[
            const SizedBox(height: 12),
            Text(
              message,
              key: const Key('door-result'),
              textAlign: TextAlign.center,
              style: epText(
                size: 12,
                weight: FontWeight.w800,
                color: Ep.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value?.toString() ?? '…', style: epDisplay(size: 28)),
      Text(
        label,
        style: epText(
          size: 9,
          weight: FontWeight.w900,
          color: Ep.contentSecondary,
        ),
      ),
    ],
  );
}
