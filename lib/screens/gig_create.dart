import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../flyer_styles.dart';
import '../models.dart';
import '../money.dart';
import '../services/flyer_text_extractor.dart';
import '../services/media_picker.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import '../widgets/slot_card.dart';
import 'gig_create_preview.dart';
import 'gig_create_sheets.dart';

Future<void> _pickGigFlyerArt(BuildContext context) async {
  final app = context.read<AppState>();
  final media = context.read<BandMediaController>();
  final PickedMedia? picked;
  try {
    picked = await media.pickFlyerArt();
  } on MediaPickException catch (error) {
    if (!context.mounted) return;
    app.say(error.message);
    return;
  }
  if (!context.mounted || picked == null) return;

  final extractionFuture = _extractFlyerProposal(app, picked);
  app.setGfFlyerArt(picked);
  app.setGfFlyerUploading(true);
  final storageId = await media.uploadFlyerArt(app.bandId, picked);
  if (identical(app.gfFlyerArt, picked)) {
    app.setGfFlyerStorageId(storageId);
  }
  app.setGfFlyerUploading(false);

  final proposal = await extractionFuture;
  if (!context.mounted || proposal == null) return;
  if (!proposal.hasSuggestions) {
    app.say('Flyer added. Add any details the artwork did not make clear.');
    return;
  }
  unawaited(
    showEpSheet(
      context,
      (_) => EpFormSheet(
        title: 'Review flyer details',
        child: _FlyerReviewBody(proposal: proposal),
      ),
    ),
  );
}

Future<FlyerEntryProposal?> _extractFlyerProposal(
  AppState app,
  PickedMedia picked,
) async {
  const extractor = FlyerTextExtractor();
  if (!extractor.isSupported) return null;
  try {
    final extraction = await extractor.extract(picked.bytes);
    if (extraction == null || extraction.lines.isEmpty) return null;
    final bands = await app.repository.searchBands('');
    return const FlyerEntryParser().parse(
      extraction,
      venues: app.venues,
      bands: bands,
    );
  } on PlatformException catch (error) {
    debugPrint('Flyer OCR failed: ${error.code}: ${error.message}');
    return null;
  }
}

/// Gig creation with an upright decorative poster preview and standard fields.
class GigCreateScreen extends StatefulWidget {
  const GigCreateScreen({super.key});

  @override
  State<GigCreateScreen> createState() => _GigCreateScreenState();
}

class _GigCreateScreenState extends State<GigCreateScreen> {
  final _cardName = TextEditingController();
  final _basicsForm = GlobalKey<EpFormState>();
  final _scroll = ScrollController();
  int _step = 0;
  int? _editorGeneration;
  bool _attempted = false;
  final _cardFocus = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_editorGeneration != app.gigEditorGeneration) {
      _editorGeneration = app.gigEditorGeneration;
      _step = 0;
      _attempted = false;
    }
    final name = app.gfName;
    if (_cardFocus.hasFocus || _cardName.text == name) return;
    _cardName.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cardName.dispose();
    _cardFocus.dispose();
    super.dispose();
  }

  void _showStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _attempted = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String? _stepError(AppState app) => switch (_step) {
    0 when app.gfName.trim().isEmpty => 'Enter a gig name.',
    0 when app.gfVenueId == null => 'Choose a venue.',
    0 when app.gfDate == null =>
      'Choose the date and check the doors and start times.',
    1 when app.gfPerformers.isEmpty => 'Add at least one performer.',
    2 when !app.validTicketPricing => 'Set the ticket price and capacity.',
    2 when app.gfTix == Ticketing.external && !app.validExternalTicketUrl =>
      'Enter a valid HTTPS ticket link.',
    _ => null,
  };

  void _continue() {
    final app = context.read<AppState>();
    setState(() => _attempted = true);
    if (_step == 0 && _basicsForm.currentState?.validate() != true) return;
    if (_stepError(app) != null) return;
    _showStep(_step + 1);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.gfPublished) {
      return const GigPublishedView(poster: _Poster(width: 212, height: 280));
    }
    if (app.gfPreviewing) return const GigDraftPreview();
    final guided = app.gfCreating;
    final sections = <({String title, String summary, Widget child})>[
      (
        title: 'Basics',
        summary: [
          app.gfName,
          app.gfDateLabel,
        ].where((v) => v.isNotEmpty).join(' · '),
        child: EpForm(
          key: _basicsForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GigNameField(controller: _cardName, focusNode: _cardFocus),
              const SizedBox(height: EpLayout.fieldGap),
              const _GigFields(admission: false),
            ],
          ),
        ),
      ),
      (
        title: 'Lineup',
        summary: '${app.gfPerformers.length} performers',
        child: const _LineupField(),
      ),
      (
        title: 'Admission',
        summary: '${app.gfPrice} · ${app.gfAgeRequirement.label}',
        child: const _GigFields(admission: true),
      ),
      (
        title: 'Poster and review',
        summary: 'Optional artwork and additional information',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EpDisclosure(
              title: 'Poster',
              summary: 'Optional artwork and poster style',
              child: _FlyerStudio(),
            ),
            const EpDisclosure(
              title: 'Additional information',
              summary: 'Optional details for guests',
              child: _AdditionalInfoField(),
            ),
            if (guided) ...[
              const SizedBox(height: 20),
              Text(app.gfName, style: Theme.of(context).textTheme.titleLarge),
              Text(
                '${app.gfDateLabel} · Doors ${app.gfDoorsLabel} · Start ${app.gfStartLabel}',
              ),
              if (app.gfVenueId != null) Text(app.venue(app.gfVenueId!).name),
              Text(
                '${app.gfPerformers.length} performers · ${app.gfAgeRequirement.label}',
              ),
              const SizedBox(height: 20),
              const Text(
                'Preview your listing before publishing. Artwork and additional details are optional.',
              ),
            ],
          ],
        ),
      ),
    ];
    return EpFormLayout(
      body: SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EpPageHeading(
              title: guided ? 'Create gig' : 'Edit gig',
              leading: CircleIconButton(
                icon: Icons.close,
                onTap: app.closeGigCreate,
              ),
              action: TextButton(
                onPressed: app.saveGigDraft,
                child: const Text('Save draft'),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                sentenceCase(app.gfSaveState),
                style: Theme.of(context).textTheme.epCaption,
              ),
            ),
            if (guided)
              EpFormSteps(
                labels: [for (final section in sections) section.title],
                current: _step,
                onBackToStep: _showStep,
              ),
            for (var i = 0; i < sections.length; i++)
              if (guided)
                EpFormStep(active: _step == i, child: sections[i].child)
              else
                EpDisclosure(
                  title: sections[i].title,
                  summary: sections[i].summary,
                  initiallyExpanded: i == 0,
                  child: sections[i].child,
                ),
            if (_attempted) InlineFormFeedback(error: _stepError(app)),
          ],
        ),
      ),
      footer: guided && _step < 3
          ? StickyActionBar(
              primaryLabel: 'Continue',
              onPrimary: _continue,
              secondaryLabel: _step == 0 ? null : 'Back',
              onSecondary: () => _showStep(_step - 1),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (guided)
                  TextButton(
                    onPressed: () => _showStep(2),
                    child: const Text('Back to admission'),
                  ),
                const _PublishBar(),
              ],
            ),
    );
  }
}

// ============================ the flyer ============================

/// The poster plus its press picker — the hero of the screen.
class _FlyerStudio extends StatelessWidget {
  const _FlyerStudio();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final flyer = context
        .select<AppState, ({bool custom, bool hasArt, bool showOverlay})>(
          (app) => (
            custom: app.gfCustomFlyer,
            hasArt: app.gfFlyerArt != null || app.gfFlyerUrl != null,
            showOverlay: app.gfShowOverlay,
          ),
        );
    return Column(
      children: [
        const _Poster(),
        const SizedBox(height: 12),
        const _SwatchRow(),
        if (flyer.custom) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _pickGigFlyerArt(context),
                icon: Icon(Icons.add_photo_alternate_outlined),
                label: Text(flyer.hasArt ? 'CHANGE ART' : 'ADD FLYER ART'),
              ),
              if (flyer.hasArt)
                TextButton.icon(
                  key: const ValueKey('clear-flyer-art'),
                  onPressed: () => app.setGfFlyerArt(null),
                  icon: Icon(Icons.close),
                  label: Text('Remove art'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const _OverlayToggle(),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: 250,
          child: Text(
            flyer.custom
                ? (flyer.showOverlay
                      ? 'Your flyer art previews with listing details on top.'
                      : 'Overlay off. Your art stays clean, and details still appear below.')
                : 'Use the fields below; the poster previews changes live.',
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w600,
              letterSpacing: .3,
              color: context.epColors.contentDisabled,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  final double width;
  final double height;

  const _Poster({this.width = 216, this.height = 284});

  @override
  Widget build(BuildContext context) {
    final poster = context
        .select<AppState, ({String fly, bool custom, bool showOverlay})>(
          (app) => (
            fly: app.gfFly,
            custom: app.gfCustomFlyer,
            showOverlay: app.gfShowOverlay,
          ),
        );
    final fly = context.read<AppState>().flyer(poster.fly);

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .55),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (poster.custom)
            _CustomArtSlot(base: fly.base)
          else
            FlyerBox(style: fly, radius: 0, shadow: false),
          // Readability overlay for uploaded artwork.
          if (poster.custom && poster.showOverlay)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .62),
                      Colors.black.withValues(alpha: .12),
                      Colors.black.withValues(alpha: .15),
                      Colors.black.withValues(alpha: .78),
                    ],
                    stops: const [0, .38, .52, 1],
                  ),
                ),
              ),
            ),
          if (poster.showOverlay) _PosterOverlay(ink: fly.fg),
        ],
      ),
    );
  }
}

class _CustomArtSlot extends StatelessWidget {
  final Color base;

  const _CustomArtSlot({required this.base});

  @override
  Widget build(BuildContext context) {
    final flyer = context
        .select<
          AppState,
          ({PickedMedia? art, String? persistedUrl, bool uploading})
        >(
          (app) => (
            art: app.gfFlyerArt,
            persistedUrl: app.gfFlyerUrl,
            uploading: app.gfFlyerUploading,
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : null;
        final logicalHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : null;
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

        return ColoredBox(
          color: base,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (flyer.art case final art?)
                Image.memory(
                  art.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: logicalWidth == null
                      ? null
                      : (logicalWidth * devicePixelRatio).round(),
                  cacheHeight: logicalHeight == null
                      ? null
                      : (logicalHeight * devicePixelRatio).round(),
                )
              else if (flyer.persistedUrl case final persistedUrl?)
                EpNetworkImage(
                  url: persistedUrl,
                  fit: BoxFit.cover,
                  fallback: _ArtPlaceholder(base: base),
                  cacheWidth: logicalWidth?.round(),
                  cacheHeight: logicalHeight?.round(),
                )
              else
                _ArtPlaceholder(base: base),
              if (flyer.uploading)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({required this.base});

  final Color base;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: base,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DashedBox(
          padding: const EdgeInsets.all(12),
          color: context.epColors.border,
          radius: 4,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 22,
                  color: context.epColors.contentDisabled,
                ),
                const SizedBox(height: 6),
                Text(
                  'Custom flyer preview',
                  style: epText(
                    size: 11,
                    weight: FontWeight.w900,
                    letterSpacing: .8,
                    color: context.epColors.contentDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-interactive listing details printed on the decorative poster.
class _PosterOverlay extends StatelessWidget {
  final Color ink;

  const _PosterOverlay({required this.ink});

  @override
  Widget build(BuildContext context) {
    final details = context.select<AppState, _PosterDetails>(
      (app) => (
        name: app.gfName,
        date: app.gfDate,
        dateLabel: app.gfDateLabel,
        doorsLabel: app.gfDoorsLabel,
        venue: app.gfVenueId == null ? null : app.venue(app.gfVenueId!),
        price: app.gfPrice,
        tix: app.gfTix,
        ticketPriceMinor: app.gfTicketPriceMinor,
      ),
    );
    final venue = details.venue;
    final titleStyle = epDisplay(
      size: 23,
      color: ink,
      height: 1.02,
    ).copyWith(letterSpacing: -.3);

    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              details.name.trim().isEmpty
                  ? 'YOUR GIG NAME'
                  : details.name.toUpperCase(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PosterLine(
                label: details.date == null
                    ? '+ DATE & DOORS'
                    : '${details.dateLabel.toUpperCase()} · DOORS ${details.doorsLabel}',
                unset: details.date == null,
                ink: ink,
              ),
              const SizedBox(height: 7),
              _PosterLine(
                label: venue == null
                    ? '+ VENUE'
                    : '${venue.name.toUpperCase()} · ${venue.area.toUpperCase()}',
                unset: venue == null,
                ink: ink,
              ),
              const SizedBox(height: 7),
              _PosterLine(
                label: details.tix == Ticketing.paid
                    ? 'TICKETS · ${details.ticketPriceMinor == null ? 'SET A PRICE' : Money(details.ticketPriceMinor!).label}'
                    : details.price == 'FREE'
                    ? 'FREE'
                    : '${details.price} AT THE DOOR',
                unset:
                    details.tix == Ticketing.paid &&
                    details.ticketPriceMinor == null,
                ink: ink,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The listing details the poster overlay prints.
typedef _PosterDetails = ({
  String name,
  DateTime? date,
  String dateLabel,
  String doorsLabel,
  Venue? venue,
  String price,
  Ticketing tix,
  int? ticketPriceMinor,
});

/// One detail printed on the flyer — dashed and dimmed until it is filled in.
class _PosterLine extends StatelessWidget {
  final String label;
  final bool unset;
  final Color ink;

  const _PosterLine({
    required this.label,
    required this.unset,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: epText(
        size: 10.5,
        weight: FontWeight.w800,
        letterSpacing: .6,
        color: unset ? ink.withValues(alpha: .55) : ink,
      ),
    );
    return unset
        ? DashedBox(
            expand: false,
            radius: 6,
            color: ink.withValues(alpha: .55),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: text,
          )
        : text;
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final press = context.select<AppState, ({String fly, bool custom})>(
      (app) => (fly: app.gfFly, custom: app.gfCustomFlyer),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 9,
      runSpacing: 8,
      children: [
        for (final key in flyerPicks) ...[
          Swatch(
            key: ValueKey('press-$key'),
            selected: press.fly == key,
            onTap: () => app.setGfFly(key),
            child: ClipOval(
              child: FlyerBox(
                style: app.flyer(key),
                radius: 0,
                shadow: false,
                patternScale: .6,
              ),
            ),
          ),
        ],
        Swatch(
          key: const ValueKey('press-custom'),
          selected: press.custom,
          dashed: true,
          onTap: () => app.setGfFly('custom'),
          child: Center(
            child: Icon(
              Icons.arrow_upward,
              size: 15,
              color: context.epColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Only meaningful over uploaded art: print the details, or leave them off.
class _OverlayToggle extends StatelessWidget {
  const _OverlayToggle();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final on = context.select<AppState, bool>((app) => app.gfShowOverlay);
    return EpCard(
      variant: on ? EpCardVariant.selected : EpCardVariant.standard,
      padding: EdgeInsets.zero,
      child: SwitchListTile.adaptive(
        value: on,
        onChanged: (_) => app.toggleGfOverlay(),
        title: Text('Text overlay'),
        subtitle: Text(
          on
              ? 'Name, date and venue printed on the art'
              : 'Art only. Details appear in the listing.',
        ),
      ),
    );
  }
}

// ============================ form controls ============================

class _GigNameField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _GigNameField({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return EpLabeledField(
      controller: controller,
      focusNode: focusNode,
      label: 'Gig name',
      hint: 'Riptide Release Show',
      required: true,
      onChanged: app.setGfName,
      textCapitalization: TextCapitalization.words,
    );
  }
}

class _GigFields extends StatelessWidget {
  const _GigFields({required this.admission});
  final bool admission;

  @override
  Widget build(BuildContext context) {
    final slot = context.select<AppState, _SlotValues>(
      (app) => (
        venue: app.gfVenueId == null ? null : app.venue(app.gfVenueId!),
        date: app.gfDate,
        dateLabel: app.gfDateLabel,
        doorsLabel: app.gfDoorsLabel,
        startLabel: app.gfStartLabel,
        price: app.gfPrice,
        ticketPriceMinor: app.gfTicketPriceMinor,
        tix: app.gfTix,
        cap: app.gfCap,
        ext: app.gfExt,
        validExternalUrl: app.validExternalTicketUrl,
        age: app.gfAgeRequirement,
      ),
    );
    final venue = slot.venue;
    final slots = <Widget>[
      SlotCard(
        key: const ValueKey('gig-slot-date'),
        tag: 'DATE',
        value: slot.date == null ? 'REQUIRED' : slot.dateLabel.toUpperCase(),
        sub: slot.date == null ? 'Choose a date' : 'Calendar date for doors',
        state: slot.date == null ? SlotState.needed : SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-times'),
        tag: 'TIMES',
        value: 'Doors ${slot.doorsLabel} · Start ${slot.startLabel}',
        sub: 'A start earlier than doors is treated as after midnight',
        state: SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-venue'),
        tag: 'VENUE',
        value: venue?.name ?? 'REQUIRED',
        sub: venue?.area ?? 'Choose a venue',
        state: venue == null ? SlotState.needed : SlotState.done,
        onTap: () => showVenueSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-cover'),
        tag: 'COVER',
        value: slot.tix == Ticketing.paid
            ? 'Tickets · ${slot.ticketPriceMinor == null ? 'Set a price' : Money(slot.ticketPriceMinor!).label}'
            : slot.price,
        sub: slot.tix == Ticketing.paid
            ? 'In-app checkout'
            : slot.price == 'FREE'
            ? 'No cover'
            : 'At the door',
        state: slot.tix == Ticketing.paid && slot.ticketPriceMinor == null
            ? SlotState.needed
            : SlotState.done,
        onTap: () => slot.tix == Ticketing.paid
            ? showTicketsSheet(context)
            : showPriceSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-access'),
        tag: 'ACCESS',
        value: switch (slot.tix) {
          Ticketing.rsvp => 'In-app RSVP',
          Ticketing.external => 'External link',
          Ticketing.paid => 'Paid tickets',
        },
        sub: switch (slot.tix) {
          Ticketing.rsvp when slot.cap == 'No cap' => 'No RSVP cap',
          Ticketing.rsvp => 'RSVP cap ${slot.cap}',
          Ticketing.external => slot.ext.isEmpty ? 'Add ticket URL' : slot.ext,
          Ticketing.paid => 'In-app checkout',
        },
        state: slot.tix == Ticketing.external && !slot.validExternalUrl
            ? SlotState.needed
            : SlotState.done,
        onTap: () => showTicketsSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-audience'),
        tag: 'AUDIENCE',
        value: slot.age.label,
        sub: 'Age requirement',
        state: SlotState.done,
        onTap: () => showAgeSheet(context),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slot in admission ? slots.skip(3) : slots.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: EpLayout.fieldGap),
            child: slot,
          ),
      ],
    );
  }
}

/// What the slot grid prints for each card.
typedef _SlotValues = ({
  Venue? venue,
  DateTime? date,
  String dateLabel,
  String doorsLabel,
  String startLabel,
  String price,
  int? ticketPriceMinor,
  Ticketing tix,
  String cap,
  String ext,
  bool validExternalUrl,
  AgeRequirement age,
});

class _LineupField extends StatelessWidget {
  const _LineupField();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final performers = context.select<AppState, List<GigPerformer>>(
      (app) => app.gfPerformers,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (performers.isEmpty)
          const DashedBox(
            child: Text(
              'Add at least one performer.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: performers.length,
            onReorderItem: app.moveGigPerformer,
            itemBuilder: (context, index) {
              final performer = performers[index];
              return Padding(
                key: ValueKey(performer.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: EpCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          child: Icon(Icons.drag_handle, size: 20),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              performer.name,
                              style: epText(size: 13, weight: FontWeight.w800),
                            ),
                            Text(
                              switch (performer.kind) {
                                GigPerformerKind.band => 'EARPLUG BAND',
                                GigPerformerKind.invited => 'INVITE PENDING',
                                GigPerformerKind.text => 'TEXT-ONLY PERFORMER',
                              },
                              style: epText(
                                size: 11,
                                weight: FontWeight.w800,
                                letterSpacing: .7,
                                color:
                                    performer.kind == GigPerformerKind.invited
                                    ? context.epColors.volt
                                    : context.epColors.contentDisabled,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (performer.inviteUrl != null)
                        IconButton(
                          tooltip: 'Copy invite link',
                          onPressed: () => copyForUser(
                            context,
                            performer.inviteUrl!,
                            successMessage: 'Invite link copied.',
                          ),
                          icon: Icon(Icons.link, size: 18),
                        ),
                      MergeSemantics(
                        child: Semantics(
                          button: true,
                          label: 'Billing role for ${performer.name}',
                          child: PopupMenuButton<GigPerformerRole>(
                            key: ValueKey(
                              'gig-performer-role-target-${performer.id}',
                            ),
                            tooltip: 'Billing role',
                            initialValue: performer.role,
                            onSelected: (role) =>
                                app.setGigPerformerRole(performer.id, role),
                            itemBuilder: (_) => [
                              for (final role in GigPerformerRole.values)
                                PopupMenuItem(
                                  value: role,
                                  child: Text(
                                    sentenceCase(role.name.toUpperCase()),
                                  ),
                                ),
                            ],
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: 48,
                                minWidth: 48,
                              ),
                              child: Center(
                                child: DecoratedBox(
                                  key: ValueKey(
                                    'gig-performer-role-pill-${performer.id}',
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.epColors.surfaceSelected,
                                    border: Border.all(
                                      color: context.epColors.accent,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      performer.role.name.toUpperCase(),
                                      style: epText(
                                        size: 11,
                                        weight: FontWeight.w900,
                                        color: context.epColors.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove performer',
                        onPressed: () => app.removeGigPerformer(performer.id),
                        icon: Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            label: const Text('Add band or performer'),
            icon: const Icon(Icons.add),
            onPressed: () => showEpSheet(
              context,
              (_) => const EpFormSheet(
                title: 'Add performer',
                child: _AddPerformerBody(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddPerformerBody extends StatefulWidget {
  const _AddPerformerBody();

  @override
  State<_AddPerformerBody> createState() => _AddPerformerBodyState();
}

class _AddPerformerBodyState extends State<_AddPerformerBody> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  late Future<List<Band>> _results;

  @override
  void initState() {
    super.initState();
    _results = context.read<AppState>().repository.searchBands('');
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String value) {
    setState(() {
      _results = context.read<AppState>().repository.searchBands(value.trim());
    });
  }

  Future<void> _addNamed({required bool invite}) async {
    if (_name.text.trim().isEmpty) return;
    await context.read<AppState>().addNamedGigPerformer(
      _name.text,
      invite: invite,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _search,
          onChanged: _runSearch,
          decoration: epInputDecoration(context, 'Search EarPlug bands'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          child: FutureBuilder<List<Band>>(
            future: _results,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  for (final band in snapshot.data!)
                    ListTile(
                      title: Text(band.name),
                      subtitle: Text(band.area),
                      trailing: Icon(Icons.add),
                      onTap: () async {
                        await app.addExistingGigPerformer(band.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ],
              );
            },
          ),
        ),
        Divider(),
        EpLabeledField(
          controller: _name,
          label: 'Performer name',
          hint: 'Unlisted band or performer name',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: EpLayout.fieldGap),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _addNamed(invite: false),
                child: Text('Add text only'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _addNamed(invite: true),
                child: Text('Create invite'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdditionalInfoField extends StatefulWidget {
  const _AdditionalInfoField();

  @override
  State<_AdditionalInfoField> createState() => _AdditionalInfoFieldState();
}

class _AdditionalInfoFieldState extends State<_AdditionalInfoField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: context.read<AppState>().gfDesc);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final description = context.read<AppState>().gfDesc;
    if (_focusNode.hasFocus || _controller.text == description) return;
    _controller.value = TextEditingValue(
      text: description,
      selection: TextSelection.collapsed(offset: description.length),
    );
  }

  @override
  Widget build(BuildContext context) => EpLabeledField(
    controller: _controller,
    focusNode: _focusNode,
    minLines: 4,
    maxLines: 7,
    onChanged: context.read<AppState>().setGfDescription,
    label: 'Notes for fans',
    hint: 'Accessibility, set times, parking, or anything fans should know',
    textCapitalization: TextCapitalization.sentences,
  );
}

class _FlyerReviewBody extends StatefulWidget {
  const _FlyerReviewBody({required this.proposal});

  final FlyerEntryProposal proposal;

  @override
  State<_FlyerReviewBody> createState() => _FlyerReviewBodyState();
}

class _FlyerReviewBodyState extends State<_FlyerReviewBody> {
  late bool _title = widget.proposal.title != null;
  late bool _date = widget.proposal.date != null;
  late bool _doors = widget.proposal.doors != null;
  late bool _start = widget.proposal.start != null;
  late bool _venue = widget.proposal.venueId != null;
  late bool _price = widget.proposal.price != null;
  late final Set<String> _bands = {
    for (final band in widget.proposal.bands) band.id,
  };
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final choices = <Widget>[
      if (proposal.title != null)
        _ReviewChoice(
          label: 'Gig name',
          value: proposal.title!,
          selected: _title,
          onChanged: (value) => setState(() => _title = value),
        ),
      if (proposal.date != null)
        _ReviewChoice(
          label: 'Date',
          value: dateLabel(proposal.date!),
          selected: _date,
          onChanged: (value) => setState(() => _date = value),
        ),
      if (proposal.doors != null)
        _ReviewChoice(
          label: 'Doors',
          value: _proposalTime(proposal.doors!),
          selected: _doors,
          onChanged: (value) => setState(() => _doors = value),
        ),
      if (proposal.start != null)
        _ReviewChoice(
          label: 'Start',
          value: _proposalTime(proposal.start!),
          selected: _start,
          onChanged: (value) => setState(() => _start = value),
        ),
      if (proposal.venueId != null)
        _ReviewChoice(
          label: 'Venue',
          value: proposal.venueName!,
          selected: _venue,
          onChanged: (value) => setState(() => _venue = value),
        ),
      if (proposal.price != null)
        _ReviewChoice(
          label: 'Price',
          value: proposal.price == 0 ? 'FREE' : '\$${proposal.price}',
          selected: _price,
          onChanged: (value) => setState(() => _price = value),
        ),
      for (final band in proposal.bands)
        _ReviewChoice(
          label: 'Performer',
          value: band.name,
          selected: _bands.contains(band.id),
          onChanged: (value) => setState(() {
            if (value) {
              _bands.add(band.id);
            } else {
              _bands.remove(band.id);
            }
          }),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Flyer text can be stylized or incomplete. Check each suggestion before adding it to the draft.',
          style: epText(
            size: 11,
            color: context.epColors.contentSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .48,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                ...choices,
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('View extracted text'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        proposal.rawText,
                        style: epText(
                          size: 11,
                          color: context.epColors.contentSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _applying ? null : _apply,
          child: Text(_applying ? 'ADDING…' : 'ADD SELECTED TO DRAFT'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final source = widget.proposal;
    await context.read<AppState>().applyFlyerProposal(
      FlyerEntryProposal(
        rawText: source.rawText,
        title: _title ? source.title : null,
        date: _date ? source.date : null,
        doors: _doors ? source.doors : null,
        start: _start ? source.start : null,
        venueId: _venue ? source.venueId : null,
        venueName: _venue ? source.venueName : null,
        price: _price ? source.price : null,
        bands: [
          for (final band in source.bands)
            if (_bands.contains(band.id)) band,
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  String _proposalTime(FlyerClockTime value) =>
      timeLabel(TimeOfDay(hour: value.hour, minute: value.minute));
}

class _ReviewChoice extends StatelessWidget {
  const _ReviewChoice({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: selected,
    onChanged: (value) => onChanged(value ?? false),
    title: Text(value, style: epText(size: 12.5, weight: FontWeight.w800)),
    subtitle: Text(label.toUpperCase(), style: epText(size: 11)),
    controlAffinity: ListTileControlAffinity.leading,
  );
}

class _PublishBar extends StatelessWidget {
  const _PublishBar();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final publish = context
        .select<
          AppState,
          ({String missingLabel, bool editingPublished, bool canPublish})
        >(
          (app) => (
            missingLabel: app.gigMissing.join(' + '),
            editingPublished:
                app.gfProject?.status == GigProjectStatus.published,
            canPublish: app.canPublishGig,
          ),
        );
    return StickyActionBar(
      secondaryLabel: 'Preview',
      onSecondary: app.previewGigDraft,
      primaryLabel: publish.editingPublished
          ? 'Publish updates'
          : 'Publish gig',
      onPrimary: publish.canPublish ? app.publishGig : null,
    );
  }
}
