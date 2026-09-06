import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  late Future<TicketSummary?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TicketDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticketId != widget.ticketId) _load();
  }

  void _load({bool refresh = false}) {
    _future = context.read<AppState>().loadTicket(
      widget.ticketId,
      refresh: refresh,
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _load(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    return FutureBuilder<TicketSummary?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final ticket = snapshot.data;
        if (ticket == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyNote(message: "This ticket isn't available"),
                TextButton(onPressed: app.back, child: const Text('BACK')),
              ],
            ),
          );
        }

        final (label, tone) = switch (ticket.status) {
          TicketStatus.valid => ('VALID', EpStatusPillTone.success),
          TicketStatus.used => ('CHECKED IN', EpStatusPillTone.selected),
          TicketStatus.refunded => ('REFUNDED', EpStatusPillTone.warning),
          TicketStatus.cancelled => ('CANCELLED', EpStatusPillTone.neutral),
          TicketStatus.unknown => ('UNAVAILABLE', EpStatusPillTone.neutral),
        };
        final startsAt = ticket.gig.startsAt;
        final doorsAt = ticket.gig.doorsAt;
        final checkedInAt = ticket.checkedInAt;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            headerTopPad(context),
            16,
            tabBarClearance,
          ),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                BackButton(onPressed: app.back),
                IconButton(
                  key: const Key('ticket-detail-refresh'),
                  tooltip: 'Refresh ticket',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(ticket.gig.title, style: textTheme.epPageHeading),
            const SizedBox(height: 8),
            Text(
              '${dateLabel(startsAt)} · Starts ${timeLabel(TimeOfDay.fromDateTime(startsAt))}',
              style: textTheme.epBody,
            ),
            if (doorsAt != null)
              Text(
                'Doors ${timeLabel(TimeOfDay.fromDateTime(doorsAt))}',
                style: textTheme.epCaption,
              ),
            const SizedBox(height: 8),
            Text(ticket.gig.venueName, style: textTheme.epBody),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(label: label, tone: tone),
            ),
            const SizedBox(height: 24),
            Text(
              'Show this at the door',
              textAlign: TextAlign.center,
              style: textTheme.epCaption,
            ),
            const SizedBox(height: 12),
            if (ticket.status == TicketStatus.valid)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                    key: const Key('ticket-detail-qr'),
                    data: ticket.token,
                    version: QrVersions.auto,
                    size: 256,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(color: Colors.black),
                    dataModuleStyle: const QrDataModuleStyle(
                      color: Colors.black,
                    ),
                  ),
                ),
              )
            else if (ticket.status == TicketStatus.used)
              EpCard(
                child: Text(
                  checkedInAt == null
                      ? 'Checked in'
                      : 'Checked in ${dateLabel(checkedInAt)} · ${timeLabel(TimeOfDay.fromDateTime(checkedInAt))}',
                  style: textTheme.epBody,
                ),
              )
            else
              EpCard(
                child: Text(switch (ticket.status) {
                  TicketStatus.refunded => 'This ticket was refunded.',
                  TicketStatus.cancelled => 'This ticket was cancelled.',
                  _ => 'This ticket is unavailable.',
                }, style: textTheme.epBody),
              ),
            const SizedBox(height: 24),
            EpButton(
              'EVENT PAGE',
              key: const Key('ticket-detail-event'),
              onTap: () => context.read<AppState>().openGig(ticket.gig.id),
            ),
          ],
        );
      },
    );
  }
}
