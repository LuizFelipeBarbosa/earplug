import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_sheet.dart';
import 'form_bits.dart';
import 'opportunity_labels.dart';
import 'sheets.dart';

Future<String?> showSendOfferSheet(
  BuildContext context, {
  required ApplicantRow row,
  required OpportunitySlot slot,
}) async {
  String? bookingId;
  await showEpSheet(
    context,
    (_) =>
        _SendOfferSheet(row: row, slot: slot, onSent: (id) => bookingId = id),
  );
  return bookingId;
}

class _SendOfferSheet extends StatefulWidget {
  const _SendOfferSheet({
    required this.row,
    required this.slot,
    required this.onSent,
  });

  final ApplicantRow row;
  final OpportunitySlot slot;
  final ValueChanged<String> onSent;

  @override
  State<_SendOfferSheet> createState() => _SendOfferSheetState();
}

class _SendOfferSheetState extends State<_SendOfferSheet> {
  late final TextEditingController _gross;
  final _notes = TextEditingController();
  final _message = TextEditingController();
  CancellationTemplate _cancellationTemplate = CancellationTemplate.standard;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gross = TextEditingController(
      text: (widget.slot.guaranteeMinor ~/ 100).toString(),
    );
  }

  @override
  void dispose() {
    _gross.dispose();
    _notes.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final dollars = int.tryParse(_gross.text.trim(), radix: 10);
    if (dollars == null || dollars < 0) {
      setState(() => _error = 'Enter a valid guarantee in dollars.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final notes = _notes.text.trim();
      final message = _message.text.trim();
      final bookingId = await context.read<AppState>().sendOffer(
        applicationId: widget.row.application.id,
        grossMinor: dollars * 100,
        cancellationTemplate: _cancellationTemplate,
        termsNotes: notes.isEmpty ? null : notes,
        message: message.isEmpty ? null : message,
      );
      if (!mounted) return;
      widget.onSent(bookingId);
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final askMinor = widget.row.application.askMinor;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EpSheetShell(
        heightFactor: .88,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        header: Row(
          children: [
            Expanded(
              child: Text('SEND OFFER', style: textTheme.epSectionHeading),
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
                Text(widget.row.band.name, style: textTheme.epSectionHeading),
                const SizedBox(height: 6),
                Text(
                  slotRoleLabel(widget.slot.role),
                  style: textTheme.epCaption,
                ),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'GUARANTEE (DOLLARS)',
                  hint: 'Offer guarantee in whole dollars',
                  controller: _gross,
                  fieldKey: const Key('send-offer-gross'),
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                ),
                if (askMinor != null &&
                    askMinor != widget.slot.guaranteeMinor) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Asks ${Money(askMinor).label}',
                    style: textTheme.epCaption,
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  "EarPlug's booking commission comes out of the guarantee; "
                  'the exact split shows on the booking. '
                  r'A $0 guarantee confirms on acceptance.',
                  style: textTheme.epCaption,
                ),
                const SizedBox(height: 18),
                const SectionBar(label: 'CANCELLATION TERMS'),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final template in CancellationTemplate.values)
                      EpChip(
                        key: ValueKey('send-offer-terms-${template.wireValue}'),
                        label: template.label,
                        active: _cancellationTemplate == template,
                        onTap: _submitting
                            ? null
                            : () => setState(
                                () => _cancellationTemplate = template,
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _cancellationTemplate.description,
                  style: textTheme.epCaption,
                ),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'NOTES',
                  hint: 'Optional booking terms',
                  controller: _notes,
                  fieldKey: const Key('send-offer-notes'),
                  enabled: !_submitting,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 2000,
                ),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'MESSAGE TO THE BAND',
                  hint: 'Optional message for the band',
                  controller: _message,
                  fieldKey: const Key('send-offer-message'),
                  enabled: !_submitting,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                ),
              ],
            ),
          ),
          InlineFormFeedback(
            error: _error,
            errorKey: const Key('send-offer-feedback'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('send-offer-submit'),
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'SENDING…' : 'SEND OFFER'),
          ),
        ],
      ),
    );
  }
}

String _errorMessage(Object error) =>
    serverErrorMessage(error) ?? 'Could not send the offer. Please retry.';
