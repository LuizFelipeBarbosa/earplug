import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

// ---------------------------- age ----------------------------

void showAgeSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const EpFormSheet(title: 'Age requirement', child: _AgeBody()),
  );
}

class _AgeBody extends StatelessWidget {
  const _AgeBody();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final requirement in AgeRequirement.values) ...[
          EpOptionCard(
            title: requirement.label,
            subtitle: switch (requirement) {
              AgeRequirement.allAges => 'Everyone is welcome',
              AgeRequirement.eighteenPlus => 'Guests must be 18 or older',
              AgeRequirement.twentyOnePlus => 'Guests must be 21 or older',
            },
            selected: app.gfAgeRequirement == requirement,
            onTap: () {
              app.setGfAgeRequirement(requirement);
              Navigator.pop(context);
            },
          ),
          if (requirement != AgeRequirement.twentyOnePlus)
            const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ---------------------------- when ----------------------------

void showWhenSheet(BuildContext context) {
  showEpSheet(context, (ctx) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .82,
      ),
      child: const EpFormSheet(
        title: 'When is it',
        padBody: false,
        child: _WhenBody(),
      ),
    );
  });
}

class _WhenBody extends StatelessWidget {
  const _WhenBody();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (_, index) => _Month(
              first: DateTime(today.year, today.month + index, 1),
              today: today,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 34),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.epColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DOORS',
                    style: epText(
                      size: 11,
                      weight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: app.gfDoors,
                      );
                      if (picked != null) app.setGfDoors(picked);
                    },
                    child: Text(app.gfDoorsLabel),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'START',
                    style: epText(
                      size: 11,
                      weight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: app.gfStart,
                      );
                      if (picked != null) app.setGfStart(picked);
                    },
                    child: Text(app.gfStartLabel),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final hour in const [18, 19, 20, 21, 22]) ...[
                      EpChip(
                        label:
                            'DOORS ${timeLabel(TimeOfDay(hour: hour, minute: 0))}',
                        active: app.gfDoors == TimeOfDay(hour: hour, minute: 0),
                        onTap: () =>
                            app.setGfDoors(TimeOfDay(hour: hour, minute: 0)),
                      ),
                      const SizedBox(width: 7),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 11),
              const DoneButton(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Month extends StatelessWidget {
  final DateTime first;
  final DateTime today;

  const _Month({required this.first, required this.today});

  @override
  Widget build(BuildContext context) {
    final selectedDate = context.select<AppState, DateTime?>(
      (app) => app.gfDate,
    );
    // The grid starts on Sunday; Dart weekdays run Mon(1)..Sun(7).
    final lead = first.weekday % 7;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();

    Widget cell(int slot) {
      final day = slot - lead + 1;
      if (day < 1 || day > days) return const SizedBox(height: 48);
      final date = DateTime(first.year, first.month, day);
      final past = date.isBefore(today);
      final selected = date == selectedDate;

      return Semantics(
        // Keyed by the whole date, not the day number: four months are on
        // screen at once, so '1' alone is ambiguous four times over.
        button: !past,
        selected: selected,
        enabled: !past,
        label: '${date.year}-${date.month}-$day',
        child: Material(
          color: past
              ? Colors.transparent
              : selected
              ? context.epColors.surfaceSelected
              : context.epColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: past
                  ? context.epColors.surfaceDisabled
                  : selected || date == today
                  ? context.epColors.accent
                  : context.epColors.border,
            ),
          ),
          child: InkWell(
            key: ValueKey('day-${date.year}-${date.month}-${date.day}'),
            onTap: past ? null : () => context.read<AppState>().setGfDate(date),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  '$day',
                  style: Theme.of(context).textTheme.epLabel.copyWith(
                    color: past
                        ? context.epColors.contentDisabled
                        : selected
                        ? context.epColors.contentPrimary
                        : context.epColors.contentSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget grid(int row, Widget Function(int) child) => Row(
      children: [
        for (var column = 0; column < 7; column++) ...[
          if (column > 0) const SizedBox(width: 4),
          Expanded(child: child(row * 7 + column)),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          monthLabel(first).toUpperCase(),
          style: epText(
            size: 11,
            weight: FontWeight.w900,
            letterSpacing: 1.3,
            color: context.epColors.contentDisabled,
          ),
        ),
        const SizedBox(height: 8),
        grid(
          0,
          (slot) => Text(
            const ['S', 'M', 'T', 'W', 'T', 'F', 'S'][slot],
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w900,
              letterSpacing: .5,
              color: context.epColors.contentDisabled,
            ),
          ),
        ),
        const SizedBox(height: 5),
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 4),
          grid(row, cell),
        ],
      ],
    );
  }
}

// ---------------------------- venue ----------------------------

void showVenueSheet(BuildContext context) {
  final app = context.read<AppState>();
  app.ensureVenueDirectory();
  showEpSheet(context, (ctx) {
    return EpFormSheet(
      title: 'Where is it',
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .6,
        ),
        child: Selector<AppState, (String?, List<Venue>)>(
          selector: (_, app) => (app.gfVenueId, app.venues),
          builder: (context, selection, _) {
            final (selectedVenueId, venues) = selection;
            return ListView.builder(
              shrinkWrap: true,
              itemCount: venues.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    'Venues are shared records, so the address stays consistent across '
                    "every band's listings.",
                    style: epText(
                      size: 11,
                      color: context.epColors.contentDisabled,
                      height: 1.45,
                    ),
                  );
                }

                final venue = venues[index - 1];
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: EpOptionCard(
                    title: venue.name,
                    titleCaps: true,
                    subtitle: '${venue.addr} · ${venue.area}',
                    selected: selectedVenueId == venue.id,
                    onTap: () {
                      app.setGfVenue(venue.id);
                      Navigator.pop(ctx);
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  });
}

// ---------------------------- price ----------------------------

const _presetPrices = ['FREE', '\$5', '\$8', '\$10', '\$12', '\$15'];

void showPriceSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const EpFormSheet(title: 'Cover', child: _PriceBody()),
  );
}

class _PriceBody extends StatefulWidget {
  const _PriceBody();

  @override
  State<_PriceBody> createState() => _PriceBodyState();
}

class _PriceBodyState extends State<_PriceBody> {
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    final price = context.read<AppState>().gfPrice;
    _custom = TextEditingController(
      text: _presetPrices.contains(price) ? '' : price.replaceAll('\$', ''),
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PresetNumberField(
          presets: _presetPrices,
          value: app.gfPrice,
          controller: _custom,
          hint: 'Other amount',
          unitLabel: 'AT THE DOOR',
          prefixText: '\$',
          onPreset: (price) {
            app.setGfPrice(price);
            Navigator.pop(context);
          },
          onCustomChanged: (value) {
            final amount = int.tryParse(value) ?? 0;
            app.setGfPrice(amount == 0 ? 'FREE' : '\$$amount');
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Free gigs get roughly twice the RSVPs. Sliding scale? Put the range '
          'in the gig name.',
          style: epText(
            size: 11,
            color: context.epColors.contentDisabled,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ---------------------------- tickets ----------------------------

const _presetCaps = ['No cap', '50', '100', '150'];

void showTicketsSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const EpFormSheet(
      title: 'Tickets',
      padBody: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 40),
        child: _TicketsBody(),
      ),
    ),
  );
}

class _TicketsBody extends StatefulWidget {
  const _TicketsBody();

  @override
  State<_TicketsBody> createState() => _TicketsBodyState();
}

class _TicketsBodyState extends State<_TicketsBody> {
  late final TextEditingController _cap;
  late final TextEditingController _ext;
  late final TextEditingController _ticketPrice;
  late final TextEditingController _ticketCapacity;
  FeeRates? _feeRates;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _cap = TextEditingController(
      text: _presetCaps.contains(app.gfCap) ? '' : app.gfCap,
    );
    _ext = TextEditingController(text: app.gfExt);
    final ticketPriceMinor = app.gfTicketPriceMinor;
    _ticketPrice = TextEditingController(
      text: ticketPriceMinor == null
          ? ''
          : (ticketPriceMinor / 100).toStringAsFixed(
              ticketPriceMinor % 100 == 0 ? 0 : 2,
            ),
    );
    _ticketCapacity = TextEditingController(
      text: app.gfTicketCapacity?.toString() ?? '',
    );
    unawaited(_loadFeeRates());
  }

  Future<void> _loadFeeRates() async {
    final app = context.read<AppState>();
    FeeRates? feeRates;
    try {
      feeRates = await app.repository.feeRates();
    } catch (_) {
      // Keep the existing caption when rates are unavailable.
    }
    if (!mounted) return;
    setState(() => _feeRates = feeRates);
  }

  String get _ticketingFeeCaption {
    final feeRates = _feeRates;
    var rate = '';
    if (feeRates != null && feeRates.configured) {
      final bps = feeRates.ticketingFeeBps;
      final percent = (bps / 100).toStringAsFixed(
        bps % 100 == 0 ? 0 : (bps % 10 == 0 ? 1 : 2),
      );
      rate = ' ($percent% + ${Money(feeRates.ticketingFeeFixedMinor).label})';
    }
    return 'Fans pay the EarPlug fee$rate on top · '
        'you receive the ticket price minus Stripe processing';
  }

  String? get _ticketPriceError {
    final dollars = double.tryParse(_ticketPrice.text.trim());
    return dollars == null || dollars < 1 || !(dollars * 100).isFinite
        ? 'Enter a ticket price of at least \$1.00.'
        : null;
  }

  String? get _ticketCapacityError {
    final capacity = int.tryParse(_ticketCapacity.text.trim());
    return capacity == null || capacity < 1 || capacity > 5000
        ? 'Enter a whole number from 1 to 5000.'
        : null;
  }

  @override
  void dispose() {
    _cap.dispose();
    _ext.dispose();
    _ticketPrice.dispose();
    _ticketCapacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EpOptionCard(
          title: 'In-app RSVP',
          subtitle: 'Free headcount, QR at the door, optional cap',
          selected: app.gfTix == Ticketing.rsvp,
          onTap: () => app.setGfTix(Ticketing.rsvp),
        ),
        if (app.gfTix == Ticketing.rsvp)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 10),
            child: _PresetNumberField(
              presets: _presetCaps,
              value: app.gfCap,
              controller: _cap,
              hint: 'Other cap',
              unitLabel: 'SPOTS',
              onPreset: app.setGfCap,
              onCustomChanged: (value) {
                final spots = int.tryParse(value) ?? 0;
                app.setGfCap(spots <= 0 ? 'No cap' : '$spots');
              },
            ),
          ),
        const SizedBox(height: 10),
        EpOptionCard(
          title: 'External ticket link',
          subtitle: 'DICE, Eventbrite, venue box office…',
          selected: app.gfTix == Ticketing.external,
          onTap: () => app.setGfTix(Ticketing.external),
        ),
        if (app.gfTix == Ticketing.external)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: EpLabeledField(
              controller: _ext,
              label: 'TICKET URL',
              hint: 'https://…',
              keyboardType: TextInputType.url,
              onChanged: app.setGfExt,
              errorText:
                  app.gfExt.trim().isNotEmpty && !app.validExternalTicketUrl
                  ? 'Enter a complete HTTPS URL.'
                  : null,
            ),
          ),
        const SizedBox(height: 10),
        EpCard(
          key: const Key('gig-tickets-paid'),
          variant: app.gfTix == Ticketing.paid
              ? EpCardVariant.selected
              : app.canSellTickets
              ? EpCardVariant.standard
              : EpCardVariant.disabled,
          onTap: app.canSellTickets ? () => app.setGfTix(Ticketing.paid) : null,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paid tickets',
                style: epText(size: 12.5, weight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                app.canSellTickets
                    ? 'Fans pay you directly through Stripe; EarPlug adds its fee at checkout.'
                    : app.features.bandTicketing
                    ? 'Enable ticket sales in PAYOUTS'
                    : 'Ticket sales are off',
                style: epText(
                  size: 11,
                  color: context.epColors.contentSecondary,
                ),
              ),
            ],
          ),
        ),
        if (app.gfTix == Ticketing.paid) ...[
          const SizedBox(height: EpLayout.fieldGap),
          EpFieldRow(
            first: EpLabeledField(
              fieldKey: const Key('gig-ticket-price'),
              label: 'TICKET PRICE (\$)',
              hint: '25',
              controller: _ticketPrice,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final dollars = double.tryParse(value.trim());
                app.setGfTicketPriceMinor(
                  dollars == null || dollars < 1 || !(dollars * 100).isFinite
                      ? null
                      : (dollars * 100).round(),
                );
              },
              errorText: _ticketPriceError,
            ),
            second: EpLabeledField(
              fieldKey: const Key('gig-ticket-capacity'),
              label: 'CAPACITY',
              hint: '100',
              controller: _ticketCapacity,
              keyboardType: TextInputType.number,
              onChanged: (value) =>
                  app.setGfTicketCapacity(int.tryParse(value.trim())),
              errorText: _ticketCapacityError,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _ticketingFeeCaption,
            style: Theme.of(context).textTheme.epCaption,
          ),
        ],
        const SizedBox(height: 14),
        const DoneButton(),
      ],
    );
  }
}

// ---------------------------- shared ----------------------------

/// Preset chips followed by the shared text box for a custom cover or capacity.
class _PresetNumberField extends StatelessWidget {
  const _PresetNumberField({
    required this.presets,
    required this.value,
    required this.controller,
    required this.hint,
    required this.unitLabel,
    required this.onPreset,
    required this.onCustomChanged,
    this.prefixText,
  });

  final List<String> presets;
  final String value;
  final TextEditingController controller;
  final String hint;
  final String unitLabel;

  final String? prefixText;
  final ValueChanged<String> onPreset;
  final ValueChanged<String> onCustomChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final preset in presets)
              EpChip(
                label: preset,
                active: value == preset,
                onTap: () => onPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: EpLayout.fieldGap),
        EpLabeledField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onCustomChanged,
          label: unitLabel,
          hint: hint,
          prefixText: prefixText,
        ),
      ],
    );
  }
}
