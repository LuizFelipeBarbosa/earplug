import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/map_view.dart';
import '../widgets/sheets.dart';

class OpportunityDetailScreen extends StatefulWidget {
  const OpportunityDetailScreen({super.key, required this.opportunityRef});

  final String opportunityRef;

  @override
  State<OpportunityDetailScreen> createState() =>
      _OpportunityDetailScreenState();
}

class _OpportunityDetailScreenState extends State<OpportunityDetailScreen> {
  Future<BrowseItem?>? _opportunity;
  String? _bandId;
  bool _withdrawing = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppState>();
    if (_opportunity == null || _bandId != app.bandId) {
      _bandId = app.bandId;
      _opportunity = app.resolveOpportunity(widget.opportunityRef);
    }
  }

  @override
  void didUpdateWidget(OpportunityDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opportunityRef != widget.opportunityRef) {
      _error = null;
      _opportunity = context.read<AppState>().resolveOpportunity(
        widget.opportunityRef,
      );
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _opportunity = context.read<AppState>().resolveOpportunity(
        widget.opportunityRef,
      );
    });
  }

  Future<void> _withdraw(Opportunity opportunity) async {
    if (_withdrawing) return;
    final app = context.read<AppState>();
    final bandId = app.bandId;
    setState(() => _withdrawing = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Withdraw application?'),
          content: const Text(
            'Your band will no longer be considered for this opportunity.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('KEEP'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONFIRM'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      // BrowseItem carries a status, so fetch the current application id before withdrawing.
      final applications = await app.repository.myApplications(bandId);
      final application = applications
          .where(
            (row) =>
                row.opportunity.id == opportunity.id &&
                row.application.status.isActive,
          )
          .firstOrNull;
      if (application == null) {
        _reload();
        return;
      }
      await app.repository.withdrawApplication(application.application.id);
      _reload();
      await app.refreshMyApplications();
      await app.refreshBrowse();
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  void _showApply(Opportunity opportunity) {
    final app = context.read<AppState>();
    showEpSheet(
      context,
      (_) => _ApplySheet(
        opportunity: opportunity,
        app: app,
        onSubmitted: () async {
          app.say('Application sent');
          _reload();
          await app.refreshMyApplications();
          await app.refreshBrowse();
        },
      ),
    );
  }

  void _back() {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BrowseItem?>(
      future: _opportunity,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final item = snapshot.data;
        if (item == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyNote(message: "This opportunity isn't available."),
                TextButton(onPressed: _back, child: const Text('BACK')),
              ],
            ),
          );
        }
        final opportunity = item.opportunity;
        final venue = opportunity.venue;
        final status = item.myApplicationStatus;
        final applied = status != null && status.isActive;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 24),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: BackButton(onPressed: _back),
                  ),
                  Text(
                    opportunity.title,
                    style: Theme.of(context).textTheme.epPageHeading,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${opportunity.status.wireValue.replaceAll('_', ' ').toUpperCase()} · Applications close ${_dateLabel(opportunity.applicationsCloseAt)}',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatFullDate(opportunity.startsAt.toLocal()),
                    style: Theme.of(context).textTheme.epMeta,
                  ),
                  if (item.invited) ...[
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill(
                        label: 'INVITED',
                        tone: EpStatusPillTone.selected,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (venue != null)
                    EpCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          VenueMiniMap(
                            venue: venue,
                            approximate: venue.exactAddress == null,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            venue.name,
                            style: Theme.of(context).textTheme.epSectionHeading,
                          ),
                          Text(
                            venue.area,
                            style: Theme.of(context).textTheme.epMeta,
                          ),
                        ],
                      ),
                    )
                  else if (opportunity.area.isNotEmpty)
                    Text(
                      opportunity.area,
                      style: Theme.of(context).textTheme.epMeta,
                    ),
                  const SizedBox(height: 20),
                  const SectionBar(label: 'SLOTS'),
                  for (final slot in opportunity.slots)
                    Padding(
                      key: ValueKey('opp-detail-slot-${slot.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slot.role.name.toUpperCase(),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.epSectionHeading,
                                ),
                                Text(
                                  [
                                    Money(
                                      slot.guaranteeMinor,
                                      opportunity.currency,
                                    ).label,
                                    if (slot.setLengthMin != null)
                                      '${slot.setLengthMin} min',
                                    if (slot.required) 'REQUIRED',
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.epMeta,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          StatusPill(
                            label: slot.status.name.toUpperCase(),
                            tone: slot.status == SlotStatus.open
                                ? EpStatusPillTone.success
                                : EpStatusPillTone.neutral,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  const SectionBar(label: 'STYLE'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final genre in opportunity.genres)
                        EpChip(label: genre, active: true, onTap: null),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    opportunity.ageRequirement.label,
                    style: Theme.of(context).textTheme.epMeta,
                  ),
                  const SizedBox(height: 20),
                  const SectionBar(label: 'DETAILS'),
                  if (opportunity.desc.trim().isNotEmpty)
                    Text(
                      opportunity.desc,
                      style: Theme.of(context).textTheme.epBody,
                    ),
                  if (opportunity.equipment?.trim().isNotEmpty == true)
                    LedgerRow(
                      title: 'Equipment',
                      details: [opportunity.equipment!],
                    ),
                  if (opportunity.requirements?.trim().isNotEmpty == true)
                    LedgerRow(
                      title: 'Requirements',
                      details: [opportunity.requirements!],
                    ),
                  if (opportunity.expectedAttendance != null)
                    LedgerRow(
                      title: 'Expected attendance',
                      details: ['${opportunity.expectedAttendance}'],
                    ),
                  LedgerRow(
                    title: 'Ticketing',
                    details: [
                      switch (opportunity.ticketing) {
                        OpportunityTicketing.none => 'No tickets required',
                        OpportunityTicketing.rsvp => 'RSVP',
                        OpportunityTicketing.external => 'External tickets',
                        OpportunityTicketing.paid => 'Paid tickets',
                      },
                    ],
                  ),
                  const SizedBox(height: 20),
                  const SectionBar(label: 'ORGANIZER'),
                  Text(
                    'Verified organizer',
                    style: Theme.of(context).textTheme.epMeta,
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: InlineFormFeedback(error: _error),
              ),
            StickyActionBar(
              key: applied ? null : const Key('opp-detail-apply'),
              primaryLabel: applied
                  ? 'APPLIED · ${status.wireValue.replaceAll('_', ' ').toUpperCase()}'
                  : 'APPLY',
              onPrimary: applied ? null : () => _showApply(opportunity),
              secondaryLabel: applied ? 'WITHDRAW' : null,
              secondaryKey: const Key('opp-detail-withdraw'),
              onSecondary: applied && !_withdrawing
                  ? () => _withdraw(opportunity)
                  : null,
            ),
          ],
        );
      },
    );
  }
}

class _ApplySheet extends StatefulWidget {
  const _ApplySheet({
    required this.opportunity,
    required this.app,
    required this.onSubmitted,
  });

  final Opportunity opportunity;
  final AppState app;
  final Future<void> Function() onSubmitted;

  @override
  State<_ApplySheet> createState() => _ApplySheetState();
}

class _ApplySheetState extends State<_ApplySheet> {
  late final List<String> _bands;
  late String _bandId;
  OpportunitySlot? _slot;
  final _fee = TextEditingController();
  final _availability = TextEditingController();
  final _lineup = TextEditingController();
  final _message = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bands = widget.app.myBands.where(widget.app.isAdminOf).toList();
    _bandId = widget.app.bandId;
    if (_bands.length > 1 && !_bands.contains(_bandId)) _bandId = _bands.first;
    _slot = widget.opportunity.slots
        .where((slot) => slot.status == SlotStatus.open)
        .firstOrNull;
    if (_slot != null) _fee.text = _feeText(_slot!);
  }

  @override
  void dispose() {
    _fee.dispose();
    _availability.dispose();
    _lineup.dispose();
    _message.dispose();
    super.dispose();
  }

  String _feeText(OpportunitySlot slot) => (slot.guaranteeMinor / 100)
      .toStringAsFixed(slot.guaranteeMinor % 100 == 0 ? 0 : 2);

  Future<void> _submit() async {
    if (_submitting || _slot == null) return;
    final amount = double.tryParse(_fee.text.trim());
    if (_fee.text.trim().isNotEmpty &&
        (amount == null || !amount.isFinite || amount < 0)) {
      setState(() => _error = 'Enter a valid requested fee.');
      return;
    }
    if (!widget.app.isAdminOf(_bandId)) {
      setState(() => _error = 'Choose a band you manage to apply.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.app.repository.applyToOpportunity(
        opportunityId: widget.opportunity.id,
        slotId: _slot!.id,
        bandId: _bandId,
        message: _message.text.trim(),
        askMinor: amount == null ? null : (amount * 100).round(),
        availabilityNote: _optionalNote(_availability),
        lineupNote: _optionalNote(_lineup),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _errorMessage(error);
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context);
    await widget.onSubmitted();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EpSheetShell(
        heightFactor: .88,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        header: Row(
          children: [
            Expanded(
              child: Text(
                'APPLY',
                style: Theme.of(context).textTheme.epSectionHeading,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        children: [
          Expanded(
            child: ListView(
              children: [
                if (_bands.length > 1) ...[
                  const SectionBar(label: 'BAND'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final id in _bands)
                        EpChip(
                          key: ValueKey('opp-apply-band-$id'),
                          label: widget.app.band(id)?.name ?? id,
                          active: _bandId == id,
                          onTap: _submitting
                              ? null
                              : () => setState(() => _bandId = id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                const SectionBar(label: 'SLOT'),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final slot in widget.opportunity.slots)
                      EpChip(
                        key: ValueKey('opp-apply-slot-${slot.id}'),
                        label:
                            '${slot.role.name.toUpperCase()} · ${Money(slot.guaranteeMinor, widget.opportunity.currency).label}',
                        active: _slot?.id == slot.id,
                        onTap: _submitting || slot.status != SlotStatus.open
                            ? null
                            : () => setState(() {
                                _slot = slot;
                                _fee.text = _feeText(slot);
                              }),
                      ),
                  ],
                ),
                if (_slot == null)
                  const EmptyNote(message: 'No slots are currently open.'),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'REQUESTED FEE (DOLLARS)',
                  hint: 'Your requested fee',
                  controller: _fee,
                  fieldKey: const Key('opp-apply-fee'),
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'AVAILABILITY',
                  hint: 'Anything we should know about timing?',
                  controller: _availability,
                  fieldKey: const Key('opp-apply-availability'),
                  enabled: !_submitting,
                ),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'LINEUP',
                  hint: 'Who will be playing?',
                  controller: _lineup,
                  fieldKey: const Key('opp-apply-lineup'),
                  enabled: !_submitting,
                ),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'MESSAGE',
                  hint: 'Tell the organizer about your band',
                  controller: _message,
                  fieldKey: const Key('opp-apply-message'),
                  enabled: !_submitting,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                ),
              ],
            ),
          ),
          if (_error != null)
            InlineFormFeedback(
              error: _error,
              errorKey: const Key('opp-apply-error'),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('opp-apply-submit'),
            onPressed: _submitting || _slot == null ? null : _submit,
            child: Text(_submitting ? 'SENDING…' : 'SUBMIT'),
          ),
        ],
      ),
    );
  }
}

String? _optionalNote(TextEditingController controller) =>
    controller.text.trim().isEmpty ? null : controller.text.trim();

String _errorMessage(Object error) =>
    error is StateError ? error.message : '$error';

String _dateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}
