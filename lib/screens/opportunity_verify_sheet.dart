import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/sheets.dart';

/// The rows of the verify sheet, in the order they read. The composer maps a
/// tapped row back to the form control that fills it.
enum OpportunityVerifyField {
  title,
  when,
  deadline,
  venue,
  slots,
  ticketing,
  visibility,
}

/// What the verify sheet shows: one already-formatted line per row.
class OpportunityVerifySummary {
  const OpportunityVerifySummary({
    required this.title,
    required this.when,
    required this.deadline,
    required this.venue,
    required this.slots,
    required this.ticketing,
    required this.visibility,
    this.isPrivate = false,
  });

  final String title;
  final String when;
  final String deadline;
  final String venue;
  final String slots;
  final String ticketing;
  final String visibility;
  final bool isPrivate;

  String label(OpportunityVerifyField field) => switch (field) {
    OpportunityVerifyField.title => 'Title',
    OpportunityVerifyField.when => 'When',
    OpportunityVerifyField.deadline => 'Apply deadline',
    OpportunityVerifyField.venue => isPrivate ? 'Location' : 'Venue',
    OpportunityVerifyField.slots => 'Slots',
    OpportunityVerifyField.ticketing => 'Ticketing',
    OpportunityVerifyField.visibility => 'Visibility',
  };

  String value(OpportunityVerifyField field) => switch (field) {
    OpportunityVerifyField.title => title,
    OpportunityVerifyField.when => when,
    OpportunityVerifyField.deadline => deadline,
    OpportunityVerifyField.venue => venue,
    OpportunityVerifyField.slots => slots,
    OpportunityVerifyField.ticketing => ticketing,
    OpportunityVerifyField.visibility => visibility,
  };
}

/// The last look before an opportunity goes live. Resolves true when the
/// organizer confirms; false when they keep editing. Tapping a summary row
/// also keeps editing and reports the row through [onEdit] so the composer
/// can scroll to it.
///
/// [publish] is true for a draft going live; an already open opportunity
/// reads "Verify & save" instead.
Future<bool> showOpportunityVerifySheet(
  BuildContext context, {
  required OpportunityVerifySummary summary,
  bool publish = true,
  ValueChanged<OpportunityVerifyField>? onEdit,
}) async {
  var confirmed = false;
  OpportunityVerifyField? edit;
  await showEpSheet(
    context,
    (sheetContext) => _VerifySheet(
      summary: summary,
      publish: publish,
      onKeepEditing: () => Navigator.pop(sheetContext),
      onEdit: (field) {
        edit = field;
        Navigator.pop(sheetContext);
      },
      onConfirm: () {
        confirmed = true;
        Navigator.pop(sheetContext);
      },
    ),
  );
  if (edit != null) onEdit?.call(edit!);
  return confirmed;
}

class _VerifySheet extends StatelessWidget {
  const _VerifySheet({
    required this.summary,
    required this.publish,
    required this.onKeepEditing,
    required this.onEdit,
    required this.onConfirm,
  });

  final OpportunityVerifySummary summary;
  final bool publish;
  final VoidCallback onKeepEditing;
  final ValueChanged<OpportunityVerifyField> onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return EpSheetShell(
      key: const ValueKey('opp-verify-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      maxHeightFactor: .92,
      scrollable: true,
      mainAxisSize: MainAxisSize.min,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpDisplay(publish ? 'Verify & publish' : 'Verify & save', size: 24),
          const SizedBox(height: 6),
          EpMonoText(
            'Check it once. This is exactly what artists see when it goes live.',
            keepCase: true,
            color: palette.muted,
          ),
          const SizedBox(height: 12),
        ],
      ),
      children: [
        const EpHairline(),
        for (final field in OpportunityVerifyField.values)
          _SummaryRow(
            key: ValueKey('opp-verify-${field.name}'),
            label: summary.label(field),
            value: summary.value(field),
            onTap: () => onEdit(field),
          ),
        const SizedBox(height: 16),
        EpMonoText(
          'Publishing saves everything in one step — no draft gate, no going back to save first.',
          keepCase: true,
          color: palette.muted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            EpPill(
              key: const ValueKey('opp-verify-keep'),
              label: 'Keep editing',
              variant: EpPillVariant.outline,
              size: EpPillSize.large,
              onPressed: onKeepEditing,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EpPill(
                key: const ValueKey('opp-verify-publish'),
                label: publish ? 'Publish' : 'Save changes',
                variant: EpPillVariant.primary,
                size: EpPillSize.large,
                expand: true,
                onPressed: onConfirm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One hairline line of the summary: eyebrow, value, tap to jump back to it.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        EpEyebrow(label),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.epBody.copyWith(
                            color: palette.contentPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: palette.contentSecondary,
                  ),
                ],
              ),
            ),
            const EpHairline(),
          ],
        ),
      ),
    );
  }
}
