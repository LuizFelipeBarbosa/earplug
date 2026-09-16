import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../genres.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import 'opportunity_detail.dart';
import 'opportunity_verify_sheet.dart';

/// The pinned action zone's height above the safe area: EpBottomCta's
/// 20/32 vertical padding around one row of large pills.
const double _actionZoneHeight = 20 + 52 + 32;

/// Room the list keeps below its last control so it can scroll clear of the
/// pinned action zone (the zone plus a 16pt gap; the safe inset is added
/// separately).
const double _footerClearance = _actionZoneHeight + 16;

/// How long the composer waits after the last edit before saving it.
const _autosaveDelay = Duration(milliseconds: 600);

/// The four rows an organizer must fill before a draft can go live.
enum _RequiredField {
  title,
  when,
  location,
  slots;

  static const rows = values;
}

/// Where the draft stands against the server, read next to the readiness
/// line.
enum _SaveState { idle, unsaved, saving, saved, failed }

const _deadlineNeed = 'a deadline before start';
const _ticketPriceNeed = 'a ticket price';
const _ticketCapacityNeed = 'a ticket capacity';

class OpportunityEditScreen extends StatefulWidget {
  const OpportunityEditScreen({super.key, required this.opportunityId});

  final String opportunityId;

  @override
  State<OpportunityEditScreen> createState() => _OpportunityEditScreenState();
}

class _OpportunityEditScreenState extends State<OpportunityEditScreen> {
  final _scroll = ScrollController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _equipment = TextEditingController();
  final _requirements = TextEditingController();
  final _attendance = TextEditingController();
  final _externalUrl = TextEditingController();
  final _ticketPrice = TextEditingController();
  final _ticketCapacity = TextEditingController();
  final _venueSearch = TextEditingController();
  final _bands = <String, Band>{};
  final _pendingInvites = <String>{};
  final _invitedIds = <String>[];
  final _slots = <_SlotDraft>[];
  final _genres = <String>{};
  // Required rows whose controls are unfolded under them; unfilled rows start
  // open so a new draft shows every control at once.
  final _expanded = <_RequiredField>{};
  final _rowKeys = {for (final row in _RequiredField.rows) row: GlobalKey()};
  final _ticketingKey = GlobalKey();
  final _visibilityKey = GlobalKey();
  bool _detailsExpanded = false;

  ({String opportunityId, String slug})? _saved;
  String? get _savedId => _saved?.opportunityId;
  int _revision = 0;
  String _savedTitle = '';
  OpportunityStatus _status = OpportunityStatus.draft;
  List<Venue> _venues = const [];
  String? _venueId;
  VenueConsent? _venueConsent;
  List<PrivateLocation> _privateLocations = const [];
  String? _privateLocationId;
  bool _isPrivate = false;
  DateTime? _date;
  TimeOfDay _doors = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay _start = const TimeOfDay(hour: 21, minute: 0);
  DateTime? _deadline;
  bool _deadlineTouched = false;
  AgeRequirement _age = AgeRequirement.allAges;
  OpportunityTicketing _ticketing = OpportunityTicketing.rsvp;
  FeeRates? _feeRates;
  OpportunityVisibility _visibility = OpportunityVisibility.publicListing;
  String? _loadedKey;
  String? _loadError;
  String? _error;
  String? _success;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;

  // Autosave: every edit bumps `_edits`; a persist only clears `_dirty` when
  // no edit landed while it was in flight.
  int _edits = 0;
  Timer? _autosaveTimer;
  Future<void>? _inflightSave;
  _SaveState _saveState = _SaveState.idle;

  // The pending ring that REVIEW & PUBLISH last pointed at; the token bumps
  // so the same row can pulse again.
  _RequiredField? _pulsing;
  int _pulseToken = 0;

  bool get _editable => switch (_status) {
    OpportunityStatus.draft ||
    OpportunityStatus.open ||
    OpportunityStatus.applicationsClosed => true,
    _ => false,
  };

  bool get _ticketingEditable =>
      (_status == OpportunityStatus.confirmed ||
          _status == OpportunityStatus.booking) &&
      _ticketing == OpportunityTicketing.paid;

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

  DateTime? _atTime(TimeOfDay time) {
    final date = _date;
    return date == null
        ? null
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime? get _startsAt => _atTime(_start);
  bool get _validDeadline =>
      _deadline != null && _startsAt != null && _deadline!.isBefore(_startsAt!);

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

  bool get _locationChosen =>
      _isPrivate ? _privateLocationId != null : _venueId != null;

  /// At least one slot, and a fee on every slot: artists apply to a number.
  bool get _slotsComplete =>
      _slots.isNotEmpty &&
      _slots.every((slot) => slot.input.guaranteeMinor > 0);

  bool _rowDone(_RequiredField row) => switch (row) {
    _RequiredField.title => _title.text.trim().isNotEmpty,
    _RequiredField.when => _date != null && _validDeadline,
    _RequiredField.location => _locationChosen,
    _RequiredField.slots => _slotsComplete,
  };

  int get _requiredDone => _RequiredField.rows.where(_rowDone).length;

  _RequiredField? get _firstPending =>
      _RequiredField.rows.where((row) => !_rowDone(row)).firstOrNull;

  List<String> get _ticketNeeds => [
    if (_ticketing == OpportunityTicketing.paid) ...[
      if (_ticketPriceError != null) _ticketPriceNeed,
      if (_ticketCapacityError != null) _ticketCapacityNeed,
    ],
  ];

  /// Whether the server would accept the form as a draft right now. A public
  /// draft needs a title, a date and a venue; a private request also needs a
  /// fee on every slot and an explicit deadline because the deposit is quoted
  /// from them. Until this holds, edits stay local and the save state says so.
  bool get _canPersist {
    if (_title.text.trim().isEmpty || _date == null || !_locationChosen) {
      return false;
    }
    if (_deadline != null && !_validDeadline) return false;
    if (_ticketNeeds.isNotEmpty) return false;
    if (_isPrivate && (!_slotsComplete || !_validDeadline)) return false;
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant OpportunityEditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureLoaded();
  }

  void _ensureLoaded() {
    final organizationId = context.read<AppState>().organizationId;
    final key = '$organizationId:${widget.opportunityId}';
    if (_loadedKey == key) return;
    _loadedKey = key;
    _saved = null;
    _load(resetExpansion: true);
  }

  Future<void> _load({bool resetExpansion = false}) async {
    final app = context.read<AppState>();
    final key = _loadedKey;
    final organizationId = app.organizationId;
    // Newly created drafts keep the "new" route until the editor is closed.
    final id = _savedId ?? widget.opportunityId;
    setState(() {
      _loading = true;
      _loadError = null;
      _feeRates = null;
    });
    unawaited(_loadFeeRates());
    try {
      final dashboard = await app.repository.organizationDashboard(
        organizationId,
      );
      final opportunity = id == 'new'
          ? null
          : await app.loadOpportunity(id, refresh: true);
      if (id != 'new' && opportunity == null) {
        throw StateError('Opportunity not found.');
      }
      if (opportunity != null && opportunity.organizationId != organizationId) {
        throw StateError('This opportunity belongs to another organization.');
      }
      final isPrivate = opportunity == null
          ? app.currentIsHost
          : opportunity.mode == OpportunityMode.privateBooking;
      // PAID ticketing unlocks off the organization's Stripe account.
      if (!isPrivate) unawaited(app.refreshOrganizationStripeStatus());
      final venueConsent =
          opportunity != null && !isPrivate && !app.currentIsVenueOperator
          ? await app.repository.venueConsentForOpportunity(opportunity.id)
          : null;
      final privateLocations = isPrivate
          ? await app.repository.privateLocationsFor(organizationId)
          : const <PrivateLocation>[];
      final bands = <String, Band>{};
      for (final bandId in opportunity?.invitedBandIds ?? <String>[]) {
        final band = await app.repository.band(bandId);
        if (band != null) bands[bandId] = band;
      }
      if (!mounted || key != _loadedKey) return;
      setState(() {
        _venues = dashboard.venues;
        _privateLocations = privateLocations;
        _bands
          ..clear()
          ..addAll(bands);
        _populate(opportunity);
        _venueConsent = venueConsent;
        if (resetExpansion) {
          _expanded
            ..clear()
            ..addAll([
              for (final row in const [
                _RequiredField.location,
                _RequiredField.slots,
              ])
                if (!_rowDone(row)) row,
            ]);
          _detailsExpanded = false;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || key != _loadedKey) return;
      setState(() {
        _loadError = _extractErrorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _reloadOpportunity() async {
    await _load();
  }

  Future<void> _loadFeeRates() async {
    final app = context.read<AppState>();
    final key = _loadedKey;
    FeeRates? feeRates;
    try {
      feeRates = await app.repository.feeRates(
        organizationId: app.organizationId,
      );
    } catch (_) {
      // Keep the existing caption when rates are unavailable.
    }
    if (!mounted || key != _loadedKey) return;
    setState(() => _feeRates = feeRates);
  }

  void _populate(Opportunity? opportunity) {
    _isPrivate = opportunity != null
        ? opportunity.mode == OpportunityMode.privateBooking
        : context.read<AppState>().currentIsHost;
    _saved = opportunity == null
        ? null
        : (opportunityId: opportunity.id, slug: opportunity.slug);
    _revision = opportunity?.revision ?? 0;
    _status = opportunity?.status ?? OpportunityStatus.draft;
    _savedTitle = opportunity?.title ?? '';
    _title.text = _savedTitle;
    _description.text = opportunity?.desc ?? '';
    _equipment.text = opportunity?.equipment ?? '';
    _requirements.text = opportunity?.requirements ?? '';
    _attendance.text = opportunity?.expectedAttendance?.toString() ?? '';
    _externalUrl.text = opportunity?.externalUrl ?? '';
    final ticketPriceMinor = opportunity?.ticketPriceMinor;
    _ticketPrice.text = ticketPriceMinor == null
        ? ''
        : (ticketPriceMinor / 100).toStringAsFixed(
            ticketPriceMinor % 100 == 0 ? 0 : 2,
          );
    _ticketCapacity.text = opportunity?.ticketCapacity?.toString() ?? '';
    _venueId = opportunity?.venueId;
    _venueSearch.clear();
    _privateLocationId = opportunity?.privateLocationId;
    _date = opportunity?.startsAt.toLocal();
    _start = opportunity == null
        ? const TimeOfDay(hour: 21, minute: 0)
        : TimeOfDay.fromDateTime(opportunity.startsAt.toLocal());
    _doors = opportunity?.doorsAt == null
        ? const TimeOfDay(hour: 20, minute: 0)
        : TimeOfDay.fromDateTime(opportunity!.doorsAt!.toLocal());
    _deadline = opportunity?.applicationsCloseAt.toLocal();
    _deadlineTouched = opportunity != null;
    _age = opportunity?.ageRequirement ?? AgeRequirement.allAges;
    _ticketing = _isPrivate
        ? OpportunityTicketing.none
        : opportunity?.ticketing ?? OpportunityTicketing.rsvp;
    _visibility =
        opportunity?.visibility ?? OpportunityVisibility.publicListing;
    _genres
      ..clear()
      ..addAll(opportunity?.genres ?? []);
    _invitedIds
      ..clear()
      ..addAll(opportunity?.invitedBandIds ?? []);
    _pendingInvites.clear();
    final previousSlots = List.of(_slots);
    _slots
      ..clear()
      ..addAll([
        for (final slot in opportunity?.slots ?? <OpportunitySlot>[])
          _SlotDraft(slot),
      ]);
    // Old TextFields detach on the next frame before their controllers retire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final slot in previousSlots) {
        slot.dispose();
      }
    });
    _dirty = false;
    _saveState = opportunity == null ? _SaveState.idle : _SaveState.saved;
    _error = null;
    _success = null;
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _scroll.dispose();
    for (final controller in [
      _title,
      _description,
      _equipment,
      _requirements,
      _attendance,
      _externalUrl,
      _ticketPrice,
      _ticketCapacity,
      _venueSearch,
    ]) {
      controller.dispose();
    }
    for (final slot in _slots) {
      slot.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- editing

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _edits++;
      _dirty = true;
      _error = null;
      _success = null;
      if (_saveState != _SaveState.saving) _saveState = _SaveState.unsaved;
    });
    _scheduleAutosave();
  }

  void _textChanged(String _) => _changed(() {});

  void _toggleRow(_RequiredField row) {
    setState(() {
      if (!_expanded.remove(row)) _expanded.add(row);
    });
  }

  // --------------------------------------------------------------- autosave

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, _autosave);
  }

  /// Saves the draft in the background: creates it the first time the server
  /// would accept it, updates it afterwards. Never touches `_busy`, so the
  /// form stays editable while it runs; a save already in flight defers this
  /// one by another delay.
  Future<void> _autosave() async {
    _autosaveTimer = null;
    if (!mounted || !_dirty || _busy || !_editable || !_canPersist) return;
    final app = context.read<AppState>();
    if (!app.canManageOrganization(app.organizationId)) return;
    if (_inflightSave != null) {
      _scheduleAutosave();
      return;
    }
    setState(() => _saveState = _SaveState.saving);
    final save = _persist(app);
    _inflightSave = save;
    try {
      await save;
      if (!mounted) return;
      setState(() {
        _saveState = _dirty ? _SaveState.unsaved : _SaveState.saved;
      });
      if (_dirty) _scheduleAutosave();
    } catch (error) {
      if (!mounted) return;
      final recovered = await _handleMutationError(app, error, reveal: false);
      if (!mounted) return;
      setState(() {
        if (!recovered) _saveState = _SaveState.failed;
      });
    } finally {
      _inflightSave = null;
    }
  }

  void _retrySave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    unawaited(_autosave());
  }

  /// Cancels the pending debounce and waits for any save in flight. Callers
  /// then persist themselves if the form is still dirty.
  Future<void> _flushAutosave() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    final inflight = _inflightSave;
    if (inflight != null) {
      try {
        await inflight;
      } catch (_) {
        // The autosave path reports its own failure.
      }
    }
  }

  Future<void> _back() async {
    final app = context.read<AppState>();
    await _flushAutosave();
    if (!mounted) return;
    final shouldSave =
        _dirty &&
        _canPersist &&
        _editable &&
        !_busy &&
        app.canManageOrganization(app.organizationId);
    if (shouldSave) {
      setState(() => _saveState = _SaveState.saving);
      try {
        await _persist(app);
      } catch (error) {
        // Stay on the form so nothing is lost silently.
        if (!mounted) return;
        setState(() => _saveState = _SaveState.failed);
        await _handleMutationError(app, error);
        return;
      }
    }
    if (mounted) app.back();
  }

  // ---------------------------------------------------------------- actions

  void _showNeeds(List<String> needs) {
    setState(() => _error = 'Still needs ${needs.join(' + ')}.');
    revealFormFeedback(this, _scroll);
  }

  /// Returns true when a revision conflict reloaded the form from the server.
  Future<bool> _handleMutationError(
    AppState app,
    Object error, {
    bool reveal = true,
  }) async {
    final message = _extractErrorMessage(error);
    var recovered = false;
    if (message.toLowerCase().contains('changed elsewhere') &&
        _savedId != null) {
      final fresh = await app.loadOpportunity(_savedId!, refresh: true);
      if (!mounted) return false;
      if (fresh != null) {
        for (final id in fresh.invitedBandIds) {
          if (_bands.containsKey(id)) continue;
          try {
            final band = await app.repository.band(id);
            if (band != null) _bands[id] = band;
          } catch (_) {
            // A missing band name must not prevent conflict recovery.
          }
        }
        if (!mounted) return false;
        setState(() => _populate(fresh));
        recovered = true;
      }
    }
    if (!mounted) return recovered;
    setState(() => _error = message);
    if (reveal) revealFormFeedback(this, _scroll);
    return recovered;
  }

  Future<void> _mutate(Future<void> Function(AppState app) action) async {
    final app = context.read<AppState>();
    if (_busy || !app.canManageOrganization(app.organizationId)) return;
    FocusScope.of(context).unfocus();
    await _flushAutosave();
    if (!mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await action(app);
    } catch (error) {
      if (mounted) await _handleMutationError(app, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persist(AppState app) async {
    final edits = _edits;
    final title = _title.text.trim();
    final slots = [for (final slot in _slots) slot.input];
    final paid = _ticketing == OpportunityTicketing.paid;
    final ticketCents = (double.tryParse(_ticketPrice.text.trim()) ?? 0) * 100;
    final ticketPriceMinor = paid
        ? (ticketCents.isFinite ? ticketCents.round() : 0)
        : null;
    final ticketCapacity = paid
        ? int.tryParse(_ticketCapacity.text.trim())
        : null;
    final ticketCurrency = paid ? 'usd' : null;
    if (_savedId == null) {
      _saved = await app.repository.createOpportunity(
        organizationId: app.organizationId,
        title: title,
        venueId: _isPrivate ? null : _venueId!,
        mode: _isPrivate
            ? OpportunityMode.privateBooking
            : OpportunityMode.publicEvent,
        privateLocationId: _isPrivate ? _privateLocationId : null,
        startsAt: _startsAt!,
        doorsAt: _atTime(_doors),
        applicationsCloseAt: _deadline,
        ageRequirement: _age,
        genres: _genres.toList(),
        desc: _description.text.trim(),
        equipment: _equipment.text.trim(),
        requirements: _requirements.text.trim(),
        expectedAttendance: int.tryParse(_attendance.text.trim()),
        visibility: _visibility,
        ticketing: _isPrivate ? OpportunityTicketing.none : _ticketing,
        ticketPriceMinor: ticketPriceMinor,
        ticketCapacity: ticketCapacity,
        ticketCurrency: ticketCurrency,
        externalUrl: _externalUrl.text.trim(),
        slots: slots,
      );
      _revision = 1;
    } else {
      _revision = await app.repository.updateOpportunity(
        opportunityId: _savedId!,
        expectedRevision: _revision,
        title: title,
        venueId: _isPrivate ? null : _venueId,
        privateLocationId: _isPrivate ? _privateLocationId : null,
        startsAt: _startsAt,
        doorsAt: _atTime(_doors),
        applicationsCloseAt: _deadline,
        ageRequirement: _age,
        genres: _genres.toList(),
        desc: _description.text.trim(),
        equipment: _equipment.text.trim(),
        requirements: _requirements.text.trim(),
        expectedAttendance: int.tryParse(_attendance.text.trim()),
        visibility: _visibility,
        ticketing: _isPrivate ? OpportunityTicketing.none : _ticketing,
        ticketPriceMinor: ticketPriceMinor,
        ticketCapacity: ticketCapacity,
        ticketCurrency: ticketCurrency,
        externalUrl: _externalUrl.text.trim(),
        slots: _status == OpportunityStatus.draft ? slots : null,
      );
    }
    _savedTitle = title;
    // An edit that landed while this save ran still needs its own save.
    if (_edits == edits) _dirty = false;
    // Retain unsuccessful invites so the next save can retry them.
    try {
      for (final id in _pendingInvites.toList()) {
        final invited = await app.repository.inviteBandToOpportunity(
          opportunityId: _savedId!,
          bandId: id,
        );
        if (!invited) {
          throw StateError('Could not invite this band. Try again.');
        }
        _pendingInvites.remove(id);
      }
    } finally {
      // Creation succeeded even if an invitation still needs to be retried.
      await app.refreshOpportunities(app.organizationId);
    }
  }

  /// Scrolls the form to [row], unfolding its controls, and pulses its
  /// pending ring when asked so the eye lands on what is missing.
  void _revealRow(_RequiredField row, {bool pulse = false}) {
    setState(() {
      if (row == _RequiredField.location || row == _RequiredField.slots) {
        _expanded.add(row);
      }
      if (pulse) {
        _pulsing = row;
        _pulseToken++;
      }
    });
    _scrollTo(_rowKeys[row]!);
  }

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = key.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else if (_scroll.hasClients) {
        // The required rows sit at the top; a row the lazy list has not built
        // yet is above the viewport.
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _editFromSummary(OpportunityVerifyField field) {
    switch (field) {
      case OpportunityVerifyField.title:
        _revealRow(_RequiredField.title);
      case OpportunityVerifyField.when || OpportunityVerifyField.deadline:
        _revealRow(_RequiredField.when);
      case OpportunityVerifyField.venue:
        _revealRow(_RequiredField.location);
      case OpportunityVerifyField.slots:
        _revealRow(_RequiredField.slots);
      case OpportunityVerifyField.ticketing:
        _scrollTo(_ticketingKey);
      case OpportunityVerifyField.visibility:
        _scrollTo(_visibilityKey);
    }
  }

  /// REVIEW & PUBLISH: never disabled. With a required row pending it points
  /// at the row; with everything done it opens the verify sheet, and a
  /// confirmed sheet publishes (or, for an open opportunity, saves).
  Future<void> _review() async {
    if (_busy || !_editable) return;
    FocusScope.of(context).unfocus();
    final pending = _firstPending;
    if (pending != null) {
      _revealRow(pending, pulse: true);
      return;
    }
    if (_ticketNeeds.isNotEmpty) {
      setState(() => _error = 'Still needs ${_ticketNeeds.join(' + ')}.');
      _scrollTo(_ticketingKey);
      return;
    }
    final app = context.read<AppState>();
    if (_waitingForVenueApproval(app)) {
      setState(() {
        _expanded.add(_RequiredField.location);
        _error = 'Still needs venue approval.';
      });
      _scrollTo(_rowKeys[_RequiredField.location]!);
      return;
    }
    await _flushAutosave();
    if (!mounted) return;
    final confirmed = await showOpportunityVerifySheet(
      context,
      summary: _summary(app),
      publish: _status == OpportunityStatus.draft,
      onEdit: _editFromSummary,
    );
    if (confirmed && mounted) await _publish();
  }

  /// Saves whatever is unsaved and, for a draft, opens it for applications —
  /// one step, no separate save first.
  Future<void> _publish() async {
    await _mutate((app) async {
      if (_dirty || _savedId == null || _pendingInvites.isNotEmpty) {
        setState(() => _saveState = _SaveState.saving);
        try {
          await _persist(app);
        } catch (_) {
          if (mounted) setState(() => _saveState = _SaveState.failed);
          rethrow;
        }
      }
      final wasDraft = _status == OpportunityStatus.draft;
      if (wasDraft) {
        final opened = await app.repository.openOpportunity(
          opportunityId: _savedId!,
          expectedRevision: _revision,
        );
        _revision = opened.revision;
        _deadline = opened.applicationsCloseAt.toLocal();
        _status = OpportunityStatus.open;
        await app.refreshOpportunities(app.organizationId);
      }
      final fresh = await app.loadOpportunity(_savedId!, refresh: true);
      if (!mounted) return;
      setState(() {
        if (fresh != null) {
          _revision = fresh.revision;
          _status = fresh.status;
        }
        _saveState = _SaveState.saved;
        _success = wasDraft
            ? 'Published — artists can apply now.'
            : 'Changes saved.';
      });
      revealFormFeedback(this, _scroll);
    });
  }

  Future<void> _requestVenueApproval() async {
    final opportunityId = _savedId;
    if (opportunityId == null || _venueId == null) return;
    await _mutate((app) async {
      var requested = false;
      await showEpSheet(
        context,
        (_) => _VenueApprovalRequestSheet(
          onSubmit: (message) async {
            final succeeded = await app.requestVenueApproval(
              opportunityId,
              message: message,
            );
            if (succeeded) requested = true;
            return succeeded;
          },
        ),
      );
      if (requested && mounted) await _reloadOpportunity();
    });
  }

  Future<void> _withdrawVenueApproval() async {
    final consent = _venueConsent;
    if (consent == null || _status != OpportunityStatus.draft) return;
    await _mutate((app) async {
      final succeeded = await app.withdrawVenueApproval(consent.id);
      if (succeeded && mounted) await _reloadOpportunity();
    });
  }

  Future<void> _updateTicketing() async {
    if (_busy || !_ticketingEditable) return;
    final needs = [
      if (_ticketPriceError != null) _ticketPriceNeed,
      if (_ticketCapacityError != null) _ticketCapacityNeed,
    ];
    if (needs.isNotEmpty) {
      _showNeeds(needs);
      return;
    }
    await _mutate((app) async {
      final dollars = double.tryParse(_ticketPrice.text.trim()) ?? 0;
      final cents = dollars * 100;
      final capacity = int.tryParse(_ticketCapacity.text.trim()) ?? 0;
      await app.updateOpportunityTicketing(
        opportunityId: _savedId!,
        expectedRevision: _revision,
        ticketPriceMinor: cents.isFinite ? cents.round() : 0,
        ticketCapacity: capacity,
      );
      final fresh = await app.loadOpportunity(_savedId!, refresh: true);
      if (!mounted) return;
      setState(() {
        if (fresh != null) _populate(fresh);
        _success = 'Ticketing updated.';
      });
      revealFormFeedback(this, _scroll);
    });
  }

  /// Close or reopen applications on an already published opportunity.
  Future<void> _transition() async {
    if (_savedId == null || !_editable || _busy) return;
    if (_status == OpportunityStatus.applicationsClosed && !_validDeadline) {
      _showNeeds([_deadlineNeed]);
      return;
    }
    await _mutate((app) async {
      if (_dirty && _canPersist) await _persist(app);
      switch (_status) {
        case OpportunityStatus.open:
          await app.repository.closeOpportunityApplications(_savedId!);
          _status = OpportunityStatus.applicationsClosed;
        case OpportunityStatus.applicationsClosed:
          await app.repository.reopenOpportunity(
            opportunityId: _savedId!,
            applicationsCloseAt: _deadline!,
          );
          _status = OpportunityStatus.open;
        default:
          return;
      }
      await app.refreshOpportunities(app.organizationId);
      final fresh = await app.loadOpportunity(_savedId!, refresh: true);
      if (!mounted) return;
      setState(() {
        if (fresh != null) {
          _revision = fresh.revision;
          _status = fresh.status;
        }
        _saveState = _SaveState.saved;
      });
    });
  }

  Future<void> _inviteBand(Band band) async {
    if (_invitedIds.contains(band.id) || _busy || !_editable) return;
    if (_savedId == null) {
      _changed(() {
        _bands[band.id] = band;
        _invitedIds.add(band.id);
        _pendingInvites.add(band.id);
      });
      return;
    }
    await _mutate((app) async {
      final invited = await app.repository.inviteBandToOpportunity(
        opportunityId: _savedId!,
        bandId: band.id,
      );
      if (!invited) throw StateError('Could not invite this band. Try again.');
      if (!mounted) return;
      setState(() {
        _bands[band.id] = band;
        _invitedIds.add(band.id);
      });
    });
  }

  Future<void> _removeInvite(String id) async {
    if (_busy || !_editable) return;
    if (_savedId == null) {
      _changed(() {
        _invitedIds.remove(id);
        _pendingInvites.remove(id);
      });
      return;
    }
    await _mutate((app) async {
      await app.repository.uninviteBandFromOpportunity(
        opportunityId: _savedId!,
        bandId: id,
      );
      if (!mounted) return;
      setState(() {
        _invitedIds.remove(id);
        _pendingInvites.remove(id);
      });
    });
  }

  Future<void> _showInviteSheet() async {
    FocusScope.of(context).unfocus();
    final repository = context.read<AppState>().repository;
    await showEpSheet(
      context,
      (_) => EpFormSheet(
        title: 'Invite bands',
        child: _InviteBandSearch(
          repository: repository,
          invitedIds: Set.of(_invitedIds),
          onSelected: _inviteBand,
        ),
      ),
    );
  }

  Future<void> _deleteOrCancel() async {
    if (_busy) return;
    final draft = _status == OpportunityStatus.draft;
    if (!draft) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancel opportunity?'),
          content: const Text(
            'This will cancel the opportunity and its applications.',
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
      if (!mounted || confirmed != true) return;
    }
    await _mutate((app) async {
      if (_savedId != null) {
        if (draft) {
          await app.repository.deleteOpportunityDraft(_savedId!);
        } else {
          await app.repository.cancelOpportunity(_savedId!);
        }
        await app.refreshOpportunities(app.organizationId);
      }
      // Nothing left to autosave once the draft is gone.
      _dirty = false;
      if (mounted) app.back();
    });
  }

  Future<void> _showWhenSheet() async {
    FocusScope.of(context).unfocus();
    await showEpSheet(
      context,
      (_) => _WhenSheet(
        isPrivate: _isPrivate,
        date: _date,
        doors: _doors,
        start: _start,
        deadline: _deadline,
        deadlineTouched: _deadlineTouched,
        onChanged: (when) => _changed(() {
          _date = when.date;
          _doors = when.doors;
          _start = when.start;
          _deadline = when.deadline;
          _deadlineTouched = when.deadlineTouched;
        }),
      ),
    );
  }

  Future<void> _preview() async {
    FocusScope.of(context).unfocus();
    final opportunity = _previewOpportunity(context.read<AppState>());
    await showEpSheet(
      context,
      (sheetContext) => EpSheetShell(
        key: const ValueKey('opp-edit-preview-sheet'),
        heightFactor: .92,
        padding: const EdgeInsets.only(top: 12),
        header: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Expanded(child: EpEyebrow('What artists see')),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        children: [
          Expanded(
            child: OpportunityDetailPresentation(
              opportunity: opportunity,
              preview: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- labels

  Venue? _venue(AppState app) {
    final id = _venueId;
    if (id == null) return null;
    return _venues.where((venue) => venue.id == id).firstOrNull ??
        app.venue(id);
  }

  PrivateLocation? get _privateLocation => _privateLocations
      .where((location) => location.id == _privateLocationId)
      .firstOrNull;

  String? _locationLabel(AppState app) {
    if (_isPrivate) return _privateLocation?.label;
    final venue = _venue(app);
    return venue == null ? null : '${venue.name} · ${venue.area}';
  }

  bool _waitingForVenueApproval(AppState app) =>
      !app.currentIsVenueOperator &&
      !_isPrivate &&
      _status == OpportunityStatus.draft &&
      _venueId != null &&
      _venueConsent?.status != VenueConsentStatus.granted;

  String get _slotsLabel => _slots
      .map(
        (slot) =>
            '${slot.role.wireValue} ${Money(slot.input.guaranteeMinor).label}',
      )
      .join(' · ');

  String get _ticketingLabel => switch (_ticketing) {
    OpportunityTicketing.none => 'None',
    OpportunityTicketing.rsvp => 'RSVP',
    OpportunityTicketing.external =>
      'External${_externalUrl.text.trim().isEmpty ? '' : ' · ${_externalUrl.text.trim()}'}',
    OpportunityTicketing.paid =>
      'Paid · \$${_ticketPrice.text.trim()} · ${_ticketCapacity.text.trim()} cap',
  };

  OpportunityVerifySummary _summary(AppState app) {
    final venue = _venue(app);
    final capacity = venue?.capacityPublic;
    return OpportunityVerifySummary(
      isPrivate: _isPrivate,
      title: _title.text.trim(),
      when:
          '${dateLabel(_date!).toUpperCase()} · '
          'Doors ${_doors.format(context)} · Start ${_start.format(context)}',
      deadline: dateLabel(_deadline!).toUpperCase(),
      venue: _isPrivate
          ? (_privateLocation?.label ?? '')
          : '${venue?.name ?? ''}${capacity == null ? '' : ' · Cap $capacity'}',
      slots: '${_slots.length} · $_slotsLabel',
      ticketing: _isPrivate ? 'No tickets' : _ticketingLabel,
      visibility: _visibility == OpportunityVisibility.publicListing
          ? 'Public'
          : 'Invite only · ${_invitedIds.length} band${_invitedIds.length == 1 ? '' : 's'}',
    );
  }

  /// The artist-facing model built straight from the form, so the preview
  /// shows unsaved edits too.
  Opportunity _previewOpportunity(AppState app) {
    final now = DateTime.now();
    final startsAt = _startsAt ?? now;
    final venue = _isPrivate ? null : _venue(app);
    final title = _title.text.trim();
    return Opportunity(
      id: _savedId ?? 'preview',
      organizationId: app.organizationId,
      mode: _isPrivate
          ? OpportunityMode.privateBooking
          : OpportunityMode.publicEvent,
      venueId: venue?.id,
      privateLocationId: _isPrivate ? _privateLocationId : null,
      privateEvent: _isPrivate,
      venue: venue,
      title: title.isEmpty ? 'Untitled' : title,
      desc: _description.text.trim(),
      expectedAttendance: int.tryParse(_attendance.text.trim()),
      genres: _genres.toList(),
      startsAt: startsAt,
      doorsAt: _atTime(_doors),
      ageRequirement: _age,
      equipment: _equipment.text.trim(),
      requirements: _requirements.text.trim(),
      flyKey: 'xerox',
      applicationsCloseAt: _deadline ?? startsAt,
      visibility: _visibility,
      ticketing: _isPrivate ? OpportunityTicketing.none : _ticketing,
      ticketPriceMinor: _ticketing == OpportunityTicketing.paid
          ? ((double.tryParse(_ticketPrice.text.trim()) ?? 0) * 100).round()
          : null,
      ticketCapacity: _ticketing == OpportunityTicketing.paid
          ? int.tryParse(_ticketCapacity.text.trim())
          : null,
      ticketCurrency: _ticketing == OpportunityTicketing.paid ? 'usd' : null,
      externalUrl: _externalUrl.text.trim(),
      status: _status,
      slug: _saved?.slug ?? '',
      revision: _revision,
      applicationCount: 0,
      slots: [
        for (var i = 0; i < _slots.length; i++)
          OpportunitySlot(
            id: 'preview-$i',
            order: i,
            role: _slots[i].role,
            setLengthMin: _slots[i].input.setLengthMin,
            guaranteeMinor: _slots[i].input.guaranteeMinor,
            required: _slots[i].required,
            status: SlotStatus.open,
          ),
      ],
      invitedBandIds: List.of(_invitedIds),
      createdAt: now,
      updatedAt: now,
      area: _isPrivate
          ? (_privateLocation?.area ?? '')
          : (venue == null
                ? ''
                : (venue.approx.label.isEmpty
                      ? venue.area
                      : venue.approx.label)),
      venueType: _isPrivate ? VenueType.private : venue?.venueType,
      currency: 'usd',
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final palette = context.epColors;
    final isVenueOperator = app.currentIsVenueOperator;
    final canManage = app.canManageOrganization(app.organizationId);
    final enabled = canManage && _editable && !_busy;
    final ticketFieldsEnabled =
        enabled || (canManage && !_busy && _ticketingEditable);
    final draft = _status == OpportunityStatus.draft;
    final slotsEnabled = enabled && draft;
    final venueApprovalLocked =
        !_isPrivate &&
        !isVenueOperator &&
        (_venueConsent?.status == VenueConsentStatus.pending ||
            _venueConsent?.status == VenueConsentStatus.granted);
    final whenEnabled = enabled && !venueApprovalLocked;
    final showActions =
        !_loading && _loadError == null && _editable && canManage;
    final showInvites =
        _visibility == OpportunityVisibility.inviteOnly ||
        _invitedIds.isNotEmpty;

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                16,
                headerTopPad(context),
                16,
                _footerClearance + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleIconButton(
                      onTap: _busy ? null : _back,
                      icon: Icons.chevron_left,
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: EpDisplay(
                          _savedTitle.trim().isEmpty
                              ? (_isPrivate ? 'New request' : 'New opportunity')
                              : _savedTitle,
                          size: 32,
                          maxLines: 2,
                        ),
                      ),
                    ),
                    if (_savedId != null) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatusPill(
                          label: _status.wireValue.replaceAll('_', ' '),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                EpMonoText(
                  'Artists apply to slots. Fans never see this until confirmed.',
                  keepCase: true,
                  color: palette.contentSecondary,
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_loadError != null) ...[
                  Text(_loadError!),
                  TextButton(
                    onPressed: () => _load(resetExpansion: true),
                    child: const Text('RETRY'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: EpMonoText(
                          'Required — $_requiredDone of ${_RequiredField.rows.length} done',
                          key: const ValueKey('opp-edit-required-progress'),
                          color: palette.muted,
                        ),
                      ),
                      _saveStateText(palette),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _FormRow(
                    key: _rowKeys[_RequiredField.title],
                    state: _stateIcon(_RequiredField.title),
                    child: EpLabeledField(
                      fieldKey: const ValueKey('opp-edit-title'),
                      label: 'TITLE',
                      hint: 'Name the night',
                      controller: _title,
                      enabled: enabled,
                      onChanged: _textChanged,
                    ),
                  ),
                  _FormRow(
                    key: _rowKeys[_RequiredField.when],
                    rowKey: const ValueKey('opp-edit-when'),
                    label: 'WHEN',
                    value: _date == null ? null : _whenValue,
                    placeholder: 'Pick date, doors and start',
                    sub: _date == null ? null : _whenSub,
                    state: _stateIcon(_RequiredField.when),
                    onTap: whenEnabled ? _showWhenSheet : null,
                  ),
                  _FormRow(
                    key: _rowKeys[_RequiredField.location],
                    rowKey: const ValueKey('opp-edit-location'),
                    label: _isPrivate ? 'LOCATION' : 'VENUE',
                    value: _locationLabel(app),
                    placeholder: _isPrivate
                        ? 'Choose a location'
                        : 'Choose a venue',
                    state: _stateIcon(_RequiredField.location),
                    expanded: _expanded.contains(_RequiredField.location),
                    onTap: () => _toggleRow(_RequiredField.location),
                  ),
                  if (_expanded.contains(_RequiredField.location))
                    _RowBody(
                      children: _locationControls(
                        app,
                        isVenueOperator: isVenueOperator,
                        canManage: canManage,
                        draft: draft,
                        slotsEnabled: slotsEnabled,
                        venueEnabled: slotsEnabled && !venueApprovalLocked,
                        venueApprovalLocked: venueApprovalLocked,
                      ),
                    ),
                  _FormRow(
                    key: _rowKeys[_RequiredField.slots],
                    rowKey: const ValueKey('opp-edit-slots'),
                    label: 'SLOTS',
                    value: _slots.isEmpty
                        ? null
                        : '${_slots.length} slot${_slots.length == 1 ? '' : 's'}',
                    placeholder: 'Add a slot — headliner, opener, DJ…',
                    sub: _slots.isEmpty
                        ? null
                        : _slotsComplete
                        ? _slotsLabel
                        : '$_slotsLabel · every slot needs a fee',
                    state: _stateIcon(_RequiredField.slots),
                    expanded: _expanded.contains(_RequiredField.slots),
                    onTap: () => _toggleRow(_RequiredField.slots),
                  ),
                  if (_expanded.contains(_RequiredField.slots))
                    _RowBody(
                      children: [
                        if (!draft) ...[
                          Text(
                            'Slots are locked once applications are open.',
                            style: Theme.of(context).textTheme.epCaption,
                          ),
                        ],
                        for (var i = 0; i < _slots.length; i++)
                          _slotFields(i, slotsEnabled),
                        OutlinedButton.icon(
                          key: const ValueKey('opp-edit-slot-add'),
                          onPressed: slotsEnabled && _slots.length < 8
                              ? () => _changed(() => _slots.add(_SlotDraft()))
                              : null,
                          icon: const Icon(Icons.add),
                          label: const Text('ADD SLOT'),
                        ),
                      ],
                    ),
                  _FormRow(
                    rowKey: const ValueKey('opp-edit-details-toggle'),
                    label: 'DETAILS · OPTIONAL',
                    trailingText: 'Style · Age · Equipment +3',
                    expanded: _detailsExpanded,
                    onTap: () =>
                        setState(() => _detailsExpanded = !_detailsExpanded),
                  ),
                  if (_detailsExpanded)
                    _RowBody(
                      key: const ValueKey('opp-edit-details-body'),
                      children: _detailControls(enabled),
                    ),
                  if (!_isPrivate) ...[
                    Padding(
                      key: _ticketingKey,
                      padding: const EdgeInsets.only(top: 24, bottom: 12),
                      child: const EpEyebrow('Ticketing'),
                    ),
                    ..._ticketingControls(
                      app,
                      enabled: enabled,
                      canManage: canManage,
                      ticketFieldsEnabled: ticketFieldsEnabled,
                    ),
                  ],
                  Padding(
                    key: _visibilityKey,
                    padding: const EdgeInsets.only(top: 24, bottom: 12),
                    child: const EpEyebrow('Visibility'),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final visibility in OpportunityVisibility.values)
                        EpPill(
                          key: ValueKey(
                            'opp-edit-visibility-${visibility == OpportunityVisibility.publicListing ? 'public' : 'invite'}',
                          ),
                          label:
                              visibility == OpportunityVisibility.publicListing
                              ? 'Public'
                              : 'Invite only',
                          selected: _visibility == visibility,
                          onPressed: enabled
                              ? () => _changed(() => _visibility = visibility)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  EpMonoText(
                    'Public means visible to artists in Discover — never on the fan map.',
                    key: const ValueKey('opp-edit-visibility-note'),
                    keepCase: true,
                    color: palette.contentSecondary,
                  ),
                  if (showInvites) ...[
                    const EpSectionHeader(label: 'INVITE BANDS'),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final id in _invitedIds)
                          EpChip(
                            key: ValueKey('opp-edit-invite-$id'),
                            label: _bands[id]?.name ?? 'Unavailable band',
                            active: true,
                            onTap: null,
                            onRemoved: enabled ? () => _removeInvite(id) : null,
                          ),
                      ],
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('opp-edit-invite-add'),
                      onPressed: enabled ? _showInviteSheet : null,
                      icon: const Icon(Icons.add),
                      label: const Text('INVITE A BAND'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (canManage &&
                      _savedId != null &&
                      (_status == OpportunityStatus.open ||
                          _status == OpportunityStatus.applicationsClosed))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TextAction(
                        buttonKey: ValueKey(
                          _status == OpportunityStatus.open
                              ? 'opp-edit-close'
                              : 'opp-edit-reopen',
                        ),
                        label: _status == OpportunityStatus.open
                            ? 'Close applications'
                            : 'Reopen applications',
                        color: _busy ? palette.contentDisabled : palette.ink,
                        onPressed: _busy ? null : _transition,
                      ),
                    ),
                  if (canManage &&
                      _savedId != null &&
                      _status != OpportunityStatus.cancelled &&
                      _status != OpportunityStatus.completed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TextAction(
                        buttonKey: ValueKey(
                          draft ? 'opp-edit-delete' : 'opp-edit-cancel',
                        ),
                        label: draft ? 'Delete draft' : 'Cancel opportunity',
                        color: _busy
                            ? palette.contentDisabled
                            : palette.destructive,
                        onPressed: _busy ? null : _deleteOrCancel,
                      ),
                    ),
                  const SizedBox(height: 12),
                  InlineFormFeedback(
                    error: _error,
                    success: _success,
                    errorKey: const ValueKey('opp-edit-feedback'),
                  ),
                ],
              ],
            ),
          ),
          if (showActions)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: EpBottomCta(
                child: Row(
                  children: [
                    EpPill(
                      key: const ValueKey('opp-edit-preview'),
                      label: 'Preview',
                      variant: EpPillVariant.outline,
                      size: EpPillSize.large,
                      onPressed: _busy ? null : _preview,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: EpPill(
                        key: const ValueKey('opp-edit-publish'),
                        label: draft ? 'Review & publish' : 'Review & save',
                        variant: EpPillVariant.primary,
                        size: EpPillSize.large,
                        expand: true,
                        onPressed: _busy ? null : _review,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _whenValue =>
      '${dateLabel(_date!).toUpperCase()} · START ${_start.format(context)}';

  String get _whenSub {
    final deadline = _deadline == null
        ? 'Choose'
        : dateLabel(_deadline!).toUpperCase();
    final warning = _deadline != null && !_validDeadline
        ? ' · must be before start'
        : '';
    return 'Doors ${_doors.format(context)} · Apply deadline $deadline$warning';
  }

  Widget _saveStateText(EpPalette palette) {
    final label = switch (_saveState) {
      _SaveState.idle => null,
      _SaveState.unsaved => 'Draft · unsaved',
      _SaveState.saving => 'Saving…',
      _SaveState.saved =>
        _status == OpportunityStatus.draft ? 'Draft · saved' : 'Saved',
      _SaveState.failed => 'Save failed · retry',
    };
    if (label == null) return const SizedBox.shrink();
    final text = EpMonoText(
      label,
      key: const ValueKey('opp-edit-save-state'),
      color: _saveState == _SaveState.failed
          ? palette.destructive
          : palette.muted,
    );
    if (_saveState != _SaveState.failed) return text;
    return Semantics(
      button: true,
      label: 'Retry save',
      child: InkWell(
        onTap: _retrySave,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: text,
        ),
      ),
    );
  }

  Widget _stateIcon(_RequiredField row) => _rowDone(row)
      ? Icon(
          Icons.check_circle,
          key: ValueKey('opp-edit-done-${row.name}'),
          size: 18,
          color: context.epColors.success,
        )
      : _PendingRing(
          key: ValueKey('opp-edit-pulse-${row.name}'),
          pulseToken: _pulsing == row ? _pulseToken : 0,
        );

  List<Widget> _locationControls(
    AppState app, {
    required bool isVenueOperator,
    required bool canManage,
    required bool draft,
    required bool slotsEnabled,
    required bool venueEnabled,
    required bool venueApprovalLocked,
  }) {
    final caption = Theme.of(context).textTheme.epCaption;
    if (_isPrivate) {
      return [
        if (_privateLocations.isEmpty)
          EpButton(
            'ADD A LOCATION',
            key: const Key('opp-add-location'),
            kind: EpButtonKind.outline,
            onTap: slotsEnabled
                ? () => app.go(Screen.privateLocationEdit, 'new')
                : null,
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final location in _privateLocations)
                EpChip(
                  key: ValueKey('opp-location-${location.id}'),
                  label: location.label,
                  active: _privateLocationId == location.id,
                  onTap: slotsEnabled
                      ? () => _changed(() => _privateLocationId = location.id)
                      : null,
                ),
            ],
          ),
        const SizedBox(height: 8),
        Text(
          'Artists see the area only. The exact address is shared after the deposit.',
          style: caption,
        ),
      ];
    }
    final venueQuery = _venueSearch.text.trim().toLowerCase();
    final matchingVenues = isVenueOperator
        ? _venues
        : app.venues
              .where((venue) {
                return venue.verified &&
                    venue.managedByOrganizationId != null &&
                    (venueQuery.isEmpty ||
                        venue.name.toLowerCase().contains(venueQuery) ||
                        venue.area.toLowerCase().contains(venueQuery));
              })
              .take(20);
    final venueApproval = _venueApprovalStatus(_venueConsent?.status);
    return [
      if (!isVenueOperator) ...[
        EpLabeledField(
          fieldKey: const Key('opp-edit-venue-search'),
          label: 'FIND A VENUE',
          hint: 'Search by venue name or area',
          controller: _venueSearch,
          enabled: venueEnabled,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
      ],
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final venue in matchingVenues)
            EpChip(
              key: ValueKey('opp-edit-venue-${venue.id}'),
              label: venue.name,
              active: _venueId == venue.id,
              onTap: venueEnabled
                  ? () => _changed(() => _venueId = venue.id)
                  : null,
            ),
        ],
      ),
      if (venueApprovalLocked) ...[
        const SizedBox(height: 8),
        Text(
          'Withdraw the venue request before changing the venue or date.',
          style: caption,
        ),
      ],
      if (!isVenueOperator) ...[
        const SizedBox(height: 8),
        Text(
          'Only venues that have joined EarPlug can approve events.',
          style: caption,
        ),
        if (_savedId != null) ...[
          const SizedBox(height: 16),
          EpCard(
            key: const Key('opp-edit-venue-approval'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: venueApproval.label,
                    tone: venueApproval.tone,
                  ),
                ),
                if (!venueApprovalLocked) ...[
                  const SizedBox(height: 12),
                  EpButton(
                    'REQUEST VENUE APPROVAL',
                    key: const Key('opp-edit-request-approval'),
                    onTap: canManage && !_busy && _venueId != null
                        ? _requestVenueApproval
                        : null,
                  ),
                ] else if (draft) ...[
                  const SizedBox(height: 12),
                  EpButton(
                    'WITHDRAW REQUEST',
                    key: const Key('opp-edit-withdraw-approval'),
                    kind: EpButtonKind.outline,
                    onTap: canManage && !_busy && _venueConsent != null
                        ? _withdrawVenueApproval
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    ];
  }

  List<Widget> _detailControls(bool enabled) => [
    const FieldLabel('STYLE'),
    const SizedBox(height: 8),
    Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final genre in kGenres)
          EpChip(
            key: ValueKey('opp-edit-genre-$genre'),
            label: genre,
            active: _genres.contains(genre),
            onTap: enabled && (_genres.length < 5 || _genres.contains(genre))
                ? () => _changed(() {
                    if (!_genres.remove(genre)) {
                      _genres.add(genre);
                    }
                  })
                : null,
          ),
      ],
    ),
    const SizedBox(height: EpLayout.fieldGap),
    const FieldLabel('AGE'),
    const SizedBox(height: 8),
    Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final age in AgeRequirement.values)
          EpChip(
            key: ValueKey('opp-edit-age-${age.wireValue}'),
            label: age.label,
            active: _age == age,
            onTap: enabled ? () => _changed(() => _age = age) : null,
          ),
      ],
    ),
    const SizedBox(height: EpLayout.fieldGap),
    EpLabeledField(
      fieldKey: const ValueKey('opp-edit-desc'),
      label: 'DESCRIPTION',
      hint: 'Tell artists about the show',
      controller: _description,
      minLines: 3,
      maxLines: 6,
      enabled: enabled,
      onChanged: _textChanged,
    ),
    const SizedBox(height: EpLayout.fieldGap),
    EpLabeledField(
      fieldKey: const ValueKey('opp-edit-equipment'),
      label: 'EQUIPMENT',
      hint: 'Backline and equipment provided',
      controller: _equipment,
      enabled: enabled,
      onChanged: _textChanged,
    ),
    const SizedBox(height: EpLayout.fieldGap),
    EpLabeledField(
      fieldKey: const ValueKey('opp-edit-requirements'),
      label: 'REQUIREMENTS',
      hint: 'What artists should bring or know',
      controller: _requirements,
      enabled: enabled,
      onChanged: _textChanged,
    ),
    const SizedBox(height: EpLayout.fieldGap),
    EpLabeledField(
      fieldKey: const ValueKey('opp-edit-attendance'),
      label: _isPrivate ? 'EXPECTED GUESTS' : 'EXPECTED ATTENDANCE',
      hint: 'Optional',
      controller: _attendance,
      keyboardType: TextInputType.number,
      enabled: enabled,
      onChanged: _textChanged,
    ),
  ];

  List<Widget> _ticketingControls(
    AppState app, {
    required bool enabled,
    required bool canManage,
    required bool ticketFieldsEnabled,
  }) {
    final palette = context.epColors;
    final caption = Theme.of(context).textTheme.epCaption;
    final stripe = app.organizationStripeStatusFor(app.organizationId);
    final paidUnlocked =
        stripe != null &&
        (stripe.canSellTickets || stripe.state == StripeAccountState.enabled);
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final ticketing in const [
            OpportunityTicketing.none,
            OpportunityTicketing.rsvp,
            OpportunityTicketing.external,
            OpportunityTicketing.paid,
          ])
            if (ticketing == OpportunityTicketing.paid && !paidUnlocked)
              Opacity(
                opacity: .45,
                child: EpPill(
                  key: const ValueKey('opp-edit-ticketing-paid'),
                  label: 'Paid',
                  selected: _ticketing == OpportunityTicketing.paid,
                  onPressed: null,
                ),
              )
            else
              EpPill(
                key: ValueKey('opp-edit-ticketing-${ticketing.wireValue}'),
                label: ticketing.wireValue,
                selected: _ticketing == ticketing,
                onPressed: enabled
                    ? () => _changed(() => _ticketing = ticketing)
                    : null,
              ),
        ],
      ),
      if (!paidUnlocked) ...[
        const SizedBox(height: 10),
        EpMonoText(
          'PAID unlocks after Stripe — finish in ORGANIZATION › FINANCE',
          key: const ValueKey('opp-edit-paid-locked'),
          keepCase: true,
          color: palette.muted,
        ),
      ],
      if (_ticketing == OpportunityTicketing.paid) ...[
        const SizedBox(height: EpLayout.fieldGap),
        EpFieldRow(
          first: EpLabeledField(
            fieldKey: const ValueKey('opp-edit-ticket-price'),
            label: 'TICKET PRICE (\$)',
            hint: '25',
            controller: _ticketPrice,
            keyboardType: TextInputType.number,
            enabled: ticketFieldsEnabled,
            onChanged: _textChanged,
            errorText: _ticketPriceError,
          ),
          second: EpLabeledField(
            fieldKey: const ValueKey('opp-edit-ticket-capacity'),
            label: 'CAPACITY',
            hint: '100',
            controller: _ticketCapacity,
            keyboardType: TextInputType.number,
            enabled: ticketFieldsEnabled,
            onChanged: _textChanged,
            errorText: _ticketCapacityError,
          ),
        ),
        const SizedBox(height: 8),
        Text(_ticketingFeeCaption, style: caption),
        if (_ticketingEditable && canManage) ...[
          const SizedBox(height: 12),
          EpButton(
            'UPDATE TICKETING',
            key: const Key('opp-edit-update-ticketing'),
            onTap: _busy ? null : _updateTicketing,
          ),
        ],
      ],
      if (_ticketing == OpportunityTicketing.external) ...[
        const SizedBox(height: EpLayout.fieldGap),
        EpLabeledField(
          fieldKey: const ValueKey('opp-edit-external-url'),
          label: 'EXTERNAL TICKET URL',
          hint: 'https://',
          controller: _externalUrl,
          keyboardType: TextInputType.url,
          enabled: enabled,
          onChanged: _textChanged,
        ),
      ],
    ];
  }

  Widget _slotFields(int index, bool enabled) {
    final slot = _slots[index];
    return Padding(
      key: ObjectKey(slot),
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 7,
            children: [
              for (final role in SlotRole.values)
                EpChip(
                  key: ValueKey('opp-edit-slot-$index-role-${role.wireValue}'),
                  label: role.wireValue,
                  active: slot.role == role,
                  onTap: enabled
                      ? () => _changed(() => slot.role = role)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: EpLayout.fieldGap),
          EpFieldRow(
            first: EpLabeledField(
              fieldKey: ValueKey('opp-edit-slot-$index-guarantee'),
              label: 'GUARANTEE (\$)',
              hint: '0',
              controller: slot.guarantee,
              keyboardType: TextInputType.number,
              enabled: enabled,
              onChanged: _textChanged,
            ),
            second: EpLabeledField(
              fieldKey: ValueKey('opp-edit-slot-$index-length'),
              label: 'SET (MINUTES)',
              hint: 'Optional',
              controller: slot.length,
              keyboardType: TextInputType.number,
              enabled: enabled,
              onChanged: _textChanged,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SwitchRow(
                  key: ValueKey('opp-edit-slot-$index-required'),
                  label: 'REQUIRED',
                  value: slot.required,
                  onChanged: enabled
                      ? (value) => _changed(() => slot.required = value)
                      : null,
                ),
              ),
              IconButton(
                key: ValueKey('opp-edit-slot-$index-remove'),
                tooltip: 'Remove slot',
                onPressed: enabled
                    ? () {
                        _changed(() => _slots.removeAt(index));
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => slot.dispose(),
                        );
                      }
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One hairline line of the form: the row's eyebrow, its value (or an accent
/// invitation when empty), an optional right-aligned mono hint, a chevron
/// when the row opens something, and the live state icon at the far right.
/// The TITLE row passes its inline field as [child] instead of a value.
///
/// [rowKey] lands on the tappable surface so tests and the readiness scroll
/// can target the row while the outer widget carries the scroll anchor.
class _FormRow extends StatelessWidget {
  const _FormRow({
    super.key,
    this.rowKey,
    this.label,
    this.value,
    this.placeholder,
    this.sub,
    this.trailingText,
    this.state,
    this.expanded,
    this.onTap,
    this.child,
  });

  final Key? rowKey;
  final String? label;
  final String? value;
  final String? placeholder;
  final String? sub;
  final String? trailingText;
  final Widget? state;
  final bool? expanded;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child:
                child ??
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null) EpEyebrow(label!),
                    if (value != null || placeholder != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        value ?? placeholder!,
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          color: value == null
                              ? palette.accent
                              : palette.contentPrimary,
                        ),
                      ),
                    ],
                    if (sub != null) ...[
                      const SizedBox(height: 4),
                      EpMonoText(sub!, color: palette.contentSecondary),
                    ],
                  ],
                ),
          ),
          if (trailingText != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: EpMonoText(
                trailingText!,
                color: palette.muted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (onTap != null || expanded != null) ...[
            const SizedBox(width: 12),
            Icon(
              expanded == null
                  ? Icons.chevron_right
                  : expanded!
                  ? Icons.expand_less
                  : Icons.expand_more,
              size: 16,
              color: onTap == null
                  ? palette.contentDisabled
                  : palette.contentSecondary,
            ),
          ],
          if (state != null) ...[const SizedBox(width: 12), state!],
        ],
      ),
    );
    return Column(
      children: [
        Semantics(
          button: onTap != null,
          expanded: expanded,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(key: rowKey, onTap: onTap, child: content),
          ),
        ),
        const EpHairline(),
      ],
    );
  }
}

/// The controls a row folds open, kept clear of the hairline below them.
class _RowBody extends StatelessWidget {
  const _RowBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// The accent ring on a required row that is still pending. Bumping
/// [pulseToken] plays one 600 ms swell so REVIEW & PUBLISH can point at it.
class _PendingRing extends StatefulWidget {
  const _PendingRing({super.key, required this.pulseToken});

  final int pulseToken;

  @override
  State<_PendingRing> createState() => _PendingRingState();
}

class _PendingRingState extends State<_PendingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _scale = _controller.drive(
    TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 1),
    ]),
  );
  late final Animation<double> _opacity = _controller.drive(
    TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: .35), weight: 1),
      TweenSequenceItem(tween: Tween(begin: .35, end: 1.0), weight: 1),
    ]),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulseToken > 0) _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _PendingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseToken > 0 && widget.pulseToken != oldWidget.pulseToken) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.epColors.accent, width: 1.5),
        ),
      ),
    ),
  );
}

/// A quiet mono text action (close, reopen, delete, cancel) at tap size.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.buttonKey,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  /// Lands on the button itself so tests can read its enabled state.
  final Key buttonKey;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    key: buttonKey,
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    child: EpMonoText(label, color: color),
  );
}

// ------------------------------------------------------------- when sheet

typedef _When = ({
  DateTime? date,
  TimeOfDay doors,
  TimeOfDay start,
  DateTime? deadline,
  bool deadlineTouched,
});

/// One flow for the date, doors, start and apply deadline: a rolling
/// calendar, two time wheels and a deadline row. Every change lands on the
/// composer immediately; DONE just closes the sheet.
class _WhenSheet extends StatefulWidget {
  const _WhenSheet({
    required this.isPrivate,
    required this.date,
    required this.doors,
    required this.start,
    required this.deadline,
    required this.deadlineTouched,
    required this.onChanged,
  });

  final bool isPrivate;
  final DateTime? date;
  final TimeOfDay doors;
  final TimeOfDay start;
  final DateTime? deadline;
  final bool deadlineTouched;
  final ValueChanged<_When> onChanged;

  @override
  State<_WhenSheet> createState() => _WhenSheetState();
}

class _WhenSheetState extends State<_WhenSheet> {
  late DateTime? _date = widget.date;
  late TimeOfDay _doors = widget.doors;
  late TimeOfDay _start = widget.start;
  late DateTime? _deadline = widget.deadline;
  late bool _deadlineTouched = widget.deadlineTouched;

  DateTime? get _startsAt {
    final date = _date;
    return date == null
        ? null
        : DateTime(date.year, date.month, date.day, _start.hour, _start.minute);
  }

  bool get _validDeadline =>
      _deadline != null && _startsAt != null && _deadline!.isBefore(_startsAt!);

  void _apply(VoidCallback change) {
    setState(change);
    widget.onChanged((
      date: _date,
      doors: _doors,
      start: _start,
      deadline: _deadline,
      deadlineTouched: _deadlineTouched,
    ));
  }

  void _pickDay(DateTime day) => _apply(() {
    _date = day;
    // Public events default to a week of applications; a private request
    // names its own deadline because the deposit is quoted from it.
    if (!widget.isPrivate && !_deadlineTouched) {
      _deadline = DateTime(day.year, day.month, day.day - 7);
    }
  });

  Future<void> _pickDeadline() async {
    final initial =
        _deadline ?? _date ?? DateTime.now().add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 10, 12, 31),
      helpText: 'APPLICATION DEADLINE',
    );
    if (!mounted || picked == null) return;
    _apply(() {
      _deadline = picked;
      _deadlineTouched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = _date;
    // Four months ahead, stretched back or forward to keep a chosen date on
    // the calendar.
    final firstMonth = selected != null && selected.isBefore(today)
        ? DateTime(selected.year, selected.month, 1)
        : DateTime(today.year, today.month, 1);
    var monthCount = 4;
    if (selected != null) {
      final span =
          (selected.year - firstMonth.year) * 12 +
          selected.month -
          firstMonth.month +
          1;
      if (span > monthCount) monthCount = span;
    }
    final wheelDate = selected ?? today;

    Widget selectionOverlay(
      BuildContext context, {
      required int columnCount,
      required int selectedIndex,
    }) => Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: palette.border, width: 1),
        ),
      ),
    );

    Widget wheel({
      required Key key,
      required String label,
      required TimeOfDay time,
      required ValueChanged<TimeOfDay> onChanged,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpEyebrow(label),
          SizedBox(
            height: 120,
            child: CupertinoDatePicker(
              key: key,
              mode: CupertinoDatePickerMode.time,
              minuteInterval: 5,
              use24hFormat: false,
              initialDateTime: DateTime(
                wheelDate.year,
                wheelDate.month,
                wheelDate.day,
                time.hour,
                time.minute ~/ 5 * 5,
              ),
              onDateTimeChanged: (dt) =>
                  onChanged(TimeOfDay(hour: dt.hour, minute: dt.minute)),
              selectionOverlayBuilder: selectionOverlay,
            ),
          ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: EpFormSheet(
        key: const ValueKey('opp-edit-when-sheet'),
        title: 'When',
        padBody: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.separated(
                key: const ValueKey('opp-edit-date'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: monthCount,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (_, index) => _CalendarMonth(
                  first: DateTime(firstMonth.year, firstMonth.month + index, 1),
                  today: today,
                  selected: selected,
                  onPick: _pickDay,
                ),
              ),
            ),
            const EpHairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: theme.brightness,
                  primaryColor: palette.accent,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: theme.textTheme.epBody.copyWith(
                      color: palette.contentPrimary,
                      fontSize: 18,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    wheel(
                      key: const ValueKey('opp-edit-doors'),
                      label: 'DOORS',
                      time: _doors,
                      onChanged: (time) => _apply(() => _doors = time),
                    ),
                    wheel(
                      key: const ValueKey('opp-edit-start'),
                      label: 'START',
                      time: _start,
                      onChanged: (time) => _apply(() => _start = time),
                    ),
                  ],
                ),
              ),
            ),
            const EpHairline(),
            Semantics(
              button: true,
              child: InkWell(
                key: const ValueKey('opp-edit-deadline'),
                onTap: _pickDeadline,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const EpEyebrow('APPLY DEADLINE'),
                            const SizedBox(height: 4),
                            Text(
                              _deadline == null
                                  ? 'Choose'
                                  : dateLabel(_deadline!).toUpperCase(),
                              style: theme.textTheme.epBody.copyWith(
                                color: _deadline == null
                                    ? palette.accent
                                    : palette.contentPrimary,
                              ),
                            ),
                            if (_deadline != null && !_validDeadline) ...[
                              const SizedBox(height: 4),
                              EpMonoText(
                                'Must be before the start',
                                color: palette.destructive,
                              ),
                            ],
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
              ),
            ),
            const EpHairline(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 13, 16, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [DoneButton()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One month of the when sheet's calendar; past days are inert.
class _CalendarMonth extends StatelessWidget {
  const _CalendarMonth({
    required this.first,
    required this.today,
    required this.selected,
    required this.onPick,
  });

  final DateTime first;
  final DateTime today;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    // The grid starts on Sunday; Dart weekdays run Mon(1)..Sun(7).
    final lead = first.weekday % 7;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final selectedDay = selected == null
        ? null
        : DateTime(selected!.year, selected!.month, selected!.day);

    Widget cell(int slot) {
      final day = slot - lead + 1;
      if (day < 1 || day > days) return const SizedBox(height: 44);
      final date = DateTime(first.year, first.month, day);
      final past = date.isBefore(today);
      final isSelected = date == selectedDay;
      return Semantics(
        button: !past,
        selected: isSelected,
        enabled: !past,
        label: '${date.year}-${date.month}-$day',
        child: Material(
          color: past
              ? Colors.transparent
              : isSelected
              ? palette.surfaceSelected
              : palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(
              color: past
                  ? palette.surfaceDisabled
                  : isSelected || date == today
                  ? palette.accent
                  : palette.border,
            ),
          ),
          child: InkWell(
            key: ValueKey('opp-edit-day-${date.year}-${date.month}-$day'),
            onTap: past ? null : () => onPick(date),
            borderRadius: BorderRadius.zero,
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  '$day',
                  style: Theme.of(context).textTheme.epLabel.copyWith(
                    color: past
                        ? palette.contentDisabled
                        : isSelected
                        ? palette.contentPrimary
                        : palette.contentSecondary,
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
        EpEyebrow(monthLabel(first)),
        const SizedBox(height: 8),
        grid(
          0,
          (slot) => Center(
            child: EpMonoText(
              const ['S', 'M', 'T', 'W', 'T', 'F', 'S'][slot],
              size: 11,
              color: palette.muted,
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

// ------------------------------------------------------------- helpers

({String label, EpStatusPillTone tone}) _venueApprovalStatus(
  VenueConsentStatus? status,
) => switch (status) {
  VenueConsentStatus.pending => (
    label: 'Pending approval',
    tone: EpStatusPillTone.warning,
  ),
  VenueConsentStatus.granted => (
    label: 'Approved',
    tone: EpStatusPillTone.success,
  ),
  VenueConsentStatus.declined => (
    label: 'Declined',
    tone: EpStatusPillTone.warning,
  ),
  VenueConsentStatus.withdrawn => (
    label: 'Withdrawn',
    tone: EpStatusPillTone.neutral,
  ),
  VenueConsentStatus.revoked => (
    label: 'Revoked',
    tone: EpStatusPillTone.warning,
  ),
  null || VenueConsentStatus.unknown => (
    label: 'Not requested',
    tone: EpStatusPillTone.neutral,
  ),
};

class _VenueApprovalRequestSheet extends StatefulWidget {
  const _VenueApprovalRequestSheet({required this.onSubmit});

  final Future<bool> Function(String? message) onSubmit;

  @override
  State<_VenueApprovalRequestSheet> createState() =>
      _VenueApprovalRequestSheetState();
}

class _VenueApprovalRequestSheetState
    extends State<_VenueApprovalRequestSheet> {
  final _message = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final trimmed = _message.text.trim();
    final succeeded = await widget.onSubmit(trimmed.isEmpty ? null : trimmed);
    if (!mounted) return;
    if (succeeded) {
      Navigator.of(context).pop();
    } else {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: 'Request venue approval',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EpLabeledField(
            fieldKey: const Key('opp-edit-approval-message'),
            label: 'MESSAGE',
            hint: 'Add a note for the venue (optional)',
            controller: _message,
            enabled: !_submitting,
            minLines: 3,
            maxLines: 5,
          ),
          const SizedBox(height: 14),
          EpButton(
            'SEND REQUEST',
            key: const Key('opp-edit-send-approval'),
            onTap: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _SlotDraft {
  _SlotDraft([OpportunitySlot? slot])
    : role = slot?.role ?? SlotRole.support,
      required = slot?.required ?? false,
      guarantee = TextEditingController(
        text: ((slot?.guaranteeMinor ?? 0) / 100).toStringAsFixed(2),
      ),
      length = TextEditingController(
        text: slot?.setLengthMin?.toString() ?? '',
      );

  SlotRole role;
  bool required;
  final TextEditingController guarantee;
  final TextEditingController length;

  SlotInput get input {
    final dollars = double.tryParse(guarantee.text.trim()) ?? 0;
    final cents = dollars * 100;
    return SlotInput(
      role: role,
      guaranteeMinor: cents.isFinite ? cents.round() : 0,
      setLengthMin: int.tryParse(length.text.trim()),
      required: required,
    );
  }

  void dispose() {
    guarantee.dispose();
    length.dispose();
  }
}

class _InviteBandSearch extends StatefulWidget {
  const _InviteBandSearch({
    required this.repository,
    required this.invitedIds,
    required this.onSelected,
  });

  final EarplugRepository repository;
  final Set<String> invitedIds;
  final ValueChanged<Band> onSelected;

  @override
  State<_InviteBandSearch> createState() => _InviteBandSearchState();
}

class _InviteBandSearchState extends State<_InviteBandSearch> {
  final _search = TextEditingController();
  late Future<List<Band>> _results;

  @override
  void initState() {
    super.initState();
    _results = widget.repository.searchBands('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('opp-edit-invite-search'),
          controller: _search,
          decoration: epInputDecoration(context, 'Search EarPlug bands'),
          onChanged: (query) => setState(() {
            _results = widget.repository.searchBands(query.trim());
          }),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: FutureBuilder<List<Band>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(_extractErrorMessage(snapshot.error!)),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Center(child: Text('No bands found.'));
              }
              return ListView(
                children: [
                  for (final band in snapshot.data!)
                    ListTile(
                      key: ValueKey('opp-edit-invite-result-${band.id}'),
                      title: Text(band.name),
                      subtitle: Text(band.area),
                      enabled: !widget.invitedIds.contains(band.id),
                      trailing: Icon(
                        widget.invitedIds.contains(band.id)
                            ? Icons.check
                            : Icons.add,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSelected(band);
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

String _extractErrorMessage(Object error) =>
    serverErrorMessage(error) ?? error.toString();
