import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'form_bits.dart';
import 'sheets.dart';

class DisputeSheet extends StatefulWidget {
  const DisputeSheet({super.key, required this.app, required this.booking});

  final AppState app;
  final Booking booking;

  @override
  State<DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends State<DisputeSheet> {
  final _text = TextEditingController();
  late final TextEditingController _amount;
  DisputeCategory _category = DisputeCategory.noShow;
  bool _submitting = false;
  String? _error;

  bool get _organizer => widget.booking.viewerSide == BookingSide.organizer;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: (widget.booking.paidMinor / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _text.text.trim();
    if (text.length < 10 || text.length > 2000) {
      setState(() {
        _error = 'Dispute details must be between 10 and 2000 characters';
      });
      return;
    }
    int? requestedRefundMinor;
    if (_organizer) {
      final dollars = double.tryParse(_amount.text.trim());
      final minor = dollars == null ? null : dollars * 100;
      requestedRefundMinor = minor != null && minor.isFinite
          ? minor.round()
          : null;
      if (requestedRefundMinor == null ||
          requestedRefundMinor <= 0 ||
          requestedRefundMinor > widget.booking.paidMinor) {
        setState(() {
          _error =
              'The refund amount must be positive and no more than the amount paid';
        });
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.app.openDispute(
        widget.booking,
        category: _category,
        text: text,
        requestedRefundMinor: requestedRefundMinor,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error is StateError ? error.message : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: _organizer ? 'REQUEST A REFUND' : 'OPEN A DISPUTE',
      padBody: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FieldLabel('CATEGORY'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final category in const [
                  DisputeCategory.noShow,
                  DisputeCategory.lateOrShortSet,
                  DisputeCategory.misrepresentation,
                  DisputeCategory.payment,
                  DisputeCategory.safety,
                  DisputeCategory.other,
                ])
                  EpChip(
                    multiple: false,
                    key: ValueKey('dispute-category-${category.wireValue}'),
                    label: category.label.toUpperCase(),
                    active: _category == category,
                    onTap: _submitting
                        ? null
                        : () => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: EpLayout.fieldGap),
            EpLabeledField(
              fieldKey: const Key('dispute-text'),
              label: 'WHAT HAPPENED',
              hint: 'Tell us what happened',
              controller: _text,
              required: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 2000,
              enabled: !_submitting,
            ),
            if (_organizer) ...[
              const SizedBox(height: EpLayout.fieldGap),
              EpLabeledField(
                fieldKey: const Key('dispute-amount'),
                label: 'AMOUNT TO REFUND (\$)',
                hint: '0.00',
                controller: _amount,
                required: true,
                keyboardType: TextInputType.number,
                enabled: !_submitting,
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'EarPlug reviews every dispute. Payouts are held until it is resolved.',
              style: Theme.of(context).textTheme.epCaption,
            ),
            const SizedBox(height: 14),
            InlineFormFeedback(error: _error),
            const SizedBox(height: 14),
            EpButton(
              'Open dispute',
              key: const Key('dispute-submit'),
              onTap: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
