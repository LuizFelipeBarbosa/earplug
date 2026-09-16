import 'dart:async';

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

/// Room the pinned footer (hint line plus a large pill) takes at the bottom of
/// the list so the last controls can scroll clear of it.
const double _footerClearance = 168;

/// The four rows an organizer must fill before a draft can open. `slotFees`
/// is the second half of the SLOTS row: a private request needs a fee on
/// every slot, not just a slot.
enum _RequiredField {
  title,
  when,
  location,
  slots,
  slotFees;

  static const rows = [title, when, location, slots];

  String label(bool isPrivate) => switch (this) {
    _RequiredField.title => 'a title',
    _RequiredField.when => 'a date and time',
    _RequiredField.location => isPrivate ? 'a location' : 'a venue',
    _RequiredField.slots => 'a slot',
    _RequiredField.slotFees => 'a fee for every slot',
  };
}

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
  bool _stripeChargesEnabled = false;
  OpportunityVisibility _visibility = OpportunityVisibility.publicListing;
  String? _loadedKey;
  String? _loadError;
  String? _error;
  String? _success;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;

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

  List<_RequiredField> get _missingRequired => [
    if (_title.text.trim().isEmpty) _RequiredField.title,
    if (_date == null) _RequiredField.when,
    if (_isPrivate ? _privateLocationId == null : _venueId == null)
      _RequiredField.location,
    if (_slots.isEmpty) _RequiredField.slots,
    if (_isPrivate && _slots.any((slot) => slot.input.guaranteeMinor <= 0))
      _RequiredField.slotFees,
  ];

  bool _rowDone(_RequiredField row) {
    final missing = _missingRequired;
    return !missing.contains(row) &&
        (row != _RequiredField.slots ||
            !missing.contains(_RequiredField.slotFees));
  }

  List<String> get _ticketNeeds => [
    if (_ticketing == OpportunityTicketing.paid) ...[
      if (_ticketPriceError != null) _ticketPriceNeed,
      if (_ticketCapacityError != null) _ticketCapacityNeed,
    ],
  ];

  /// A public draft may be saved without slots or a valid deadline; a private
  /// request needs both because the deposit is quoted from them.
  List<String> get _saveNeeds => [
    for (final field in _missingRequired)
      if (_isPrivate || field != _RequiredField.slots) field.label(_isPrivate),
    if (_isPrivate && !_validDeadline) _deadlineNeed,
    ..._ticketNeeds,
  ];

  List<String> get _openNeeds => [
    for (final field in _missingRequired) field.label(_isPrivate),
    if (!_validDeadline) _deadlineNeed,
    ..._ticketNeeds,
  ];

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
        _stripeChargesEnabled = dashboard.verification.stripeChargesEnabled;
        _bands
          ..clear()
          ..addAll(bands);
        _populate(opportunity);
        _venueConsent = venueConsent;
        if (resetExpansion) {
          _expanded
            ..clear()
            ..addAll(
              _RequiredField.rows.where(
                (row) => row != _RequiredField.title && !_rowDone(row),
              ),
            );
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
    _error = null;
    _success = null;
  }

  @override
  void dispose() {
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

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
      _error = null;
      _success = null;
    });
  }

  void _textChanged(String _) => _changed(() {});

  void _toggleRow(_RequiredField row) {
    setState(() {
      if (!_expanded.remove(row)) _expanded.add(row);
    });
  }

  Future<void> _pickDate({bool deadline = false}) async {
    final initial =
        (deadline ? _deadline : _date) ??
        DateTime.now().add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 5),
      lastDate: DateTime(initial.year + 10, 12, 31),
      helpText: deadline ? 'APPLICATION DEADLINE' : 'EVENT DATE',
    );
    if (!mounted || picked == null) return;
    _changed(() {
      if (deadline) {
        _deadline = picked;
        _deadlineTouched = true;
      } else {
        _date = picked;
        if (!_isPrivate && !_deadlineTouched && _deadline == null) {
          _deadline = DateTime(picked.year, picked.month, picked.day - 7);
        }
      }
    });
  }

  Future<void> _pickTime({required bool doors}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: doors ? _doors : _start,
    );
    if (!mounted || picked == null) return;
    _changed(() {
      if (doors) {
        _doors = picked;
      } else {
        _start = picked;
      }
    });
  }

  void _showNeeds(List<String> needs) {
    setState(() => _error = 'Still needs ${needs.join(' + ')}.');
    revealFormFeedback(this, _scroll);
  }

  Future<void> _handleMutationError(AppState app, Object error) async {
    final message = _extractErrorMessage(error);
    if (message.toLowerCase().contains('changed elsewhere') &&
        _savedId != null) {
      final fresh = await app.loadOpportunity(_savedId!, refresh: true);
      if (!mounted) return;
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
        if (!mounted) return;
        setState(() => _populate(fresh));
      }
    }
    if (!mounted) return;
    setState(() => _error = message);
    revealFormFeedback(this, _scroll);
  }

  Future<void> _mutate(Future<void> Function(AppState app) action) async {
    final app = context.read<AppState>();
    if (_busy || !app.canManageOrganization(app.organizationId)) return;
    FocusScope.of(context).unfocus();
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
    _dirty = false;
    // Retain unsuccessful invites so another explicit save can retry them.
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

  Future<void> _save() async {
    if (_busy || !_editable) return;
    if (_saveNeeds.isNotEmpty) {
      _showNeeds(_saveNeeds);
      return;
    }
    await _mutate((app) async {
      await _persist(app);
      if (!mounted) return;
      setState(() => _success = 'Changes saved.');
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

  Future<void> _transition() async {
    if (_savedId == null || !_editable || _busy) return;
    if (_status == OpportunityStatus.draft && _openNeeds.isNotEmpty) {
      _showNeeds(_openNeeds);
      return;
    }
    if (_status == OpportunityStatus.applicationsClosed && !_validDeadline) {
      _showNeeds([_deadlineNeed]);
      return;
    }
    await _mutate((app) async {
      switch (_status) {
        case OpportunityStatus.draft:
          if (_dirty || _pendingInvites.isNotEmpty) await _persist(app);
          final opened = await app.repository.openOpportunity(
            opportunityId: _savedId!,
            expectedRevision: _revision,
          );
          _revision = opened.revision;
          _deadline = opened.applicationsCloseAt.toLocal();
          _status = OpportunityStatus.open;
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
      });
    });
  }

  Future<void> _inviteBand(Band band) async {
    if (_invitedIds.contains(band.id) || _busy || !_editable) return;
    if (_savedId == null) {
      setState(() {
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
      setState(() {
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
      if (mounted) app.back();
    });
  }

  String? _venueLabel(AppState app) {
    final id = _venueId;
    if (id == null) return null;
    final venue =
        _venues.where((venue) => venue.id == id).firstOrNull ?? app.venue(id);
    return '${venue.name} · ${venue.area}';
  }

  String? _locationLabel(AppState app) => _isPrivate
      ? _privateLocations
            .where((location) => location.id == _privateLocationId)
            .firstOrNull
            ?.label
      : _venueLabel(app);

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
    final waitingForVenueApproval =
        !isVenueOperator &&
        !_isPrivate &&
        draft &&
        _venueId != null &&
        _venueConsent?.status != VenueConsentStatus.granted;
    final needs = [
      ..._openNeeds,
      if (waitingForVenueApproval) 'venue approval',
    ];
    final requiredDone = _RequiredField.rows.where(_rowDone).length;
    final showFooter =
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
                tabBarClearance +
                    _footerClearance +
                    MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  children: [
                    CircleIconButton(onTap: app.back),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _savedTitle.trim().isEmpty
                            ? (_isPrivate ? 'NEW REQUEST' : 'NEW OPPORTUNITY')
                            : _savedTitle,
                        style: Theme.of(context).textTheme.epPageHeading,
                      ),
                    ),
                    if (_savedId != null) ...[
                      const SizedBox(width: 8),
                      StatusPill(label: _status.wireValue.replaceAll('_', ' ')),
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
                  EpReadinessBar(
                    done: requiredDone,
                    total: _RequiredField.rows.length,
                  ),
                  const SizedBox(height: 8),
                  EpEyebrow(
                    '$requiredDone of ${_RequiredField.rows.length} required done',
                    key: const ValueKey('opp-edit-required-progress'),
                  ),
                  const EpSectionHeader(label: 'REQUIRED'),
                  _FormRow(
                    done: _rowDone(_RequiredField.title),
                    child: EpLabeledField(
                      fieldKey: const ValueKey('opp-edit-title'),
                      label: 'TITLE',
                      hint: 'Name the night',
                      controller: _title,
                      required: true,
                      enabled: enabled,
                      onChanged: _textChanged,
                    ),
                  ),
                  _FormRow(
                    key: const ValueKey('opp-edit-when'),
                    label: 'WHEN',
                    done: _rowDone(_RequiredField.when),
                    value: _date == null ? null : _dateLabel(context, _date),
                    placeholder: 'Pick date, doors and start',
                    sub: _date == null
                        ? null
                        : 'Doors ${_doors.format(context)} · '
                              'Start ${_start.format(context)} · '
                              'Deadline ${_dateLabel(context, _deadline)}',
                    expanded: _expanded.contains(_RequiredField.when),
                    onTap: () => _toggleRow(_RequiredField.when),
                  ),
                  if (_expanded.contains(_RequiredField.when))
                    _RowBody(
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              key: const ValueKey('opp-edit-date'),
                              onPressed: whenEnabled ? _pickDate : null,
                              child: Text(
                                'DATE · ${_dateLabel(context, _date)}',
                              ),
                            ),
                            OutlinedButton(
                              key: const ValueKey('opp-edit-doors'),
                              onPressed: whenEnabled
                                  ? () => _pickTime(doors: true)
                                  : null,
                              child: Text('DOORS · ${_doors.format(context)}'),
                            ),
                            OutlinedButton(
                              key: const ValueKey('opp-edit-start'),
                              onPressed: whenEnabled
                                  ? () => _pickTime(doors: false)
                                  : null,
                              child: Text('START · ${_start.format(context)}'),
                            ),
                            OutlinedButton(
                              key: const ValueKey('opp-edit-deadline'),
                              onPressed: whenEnabled
                                  ? () => _pickDate(deadline: true)
                                  : null,
                              child: Text(
                                'DEADLINE · ${_dateLabel(context, _deadline)}',
                              ),
                            ),
                          ],
                        ),
                        if (venueApprovalLocked) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Withdraw the venue request before changing the venue or date.',
                            style: Theme.of(context).textTheme.epCaption,
                          ),
                        ],
                      ],
                    ),
                  _FormRow(
                    key: const ValueKey('opp-edit-location'),
                    label: _isPrivate ? 'LOCATION' : 'VENUE',
                    done: _rowDone(_RequiredField.location),
                    value: _locationLabel(app),
                    placeholder: _isPrivate
                        ? 'Choose a location'
                        : 'Choose a venue',
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
                    key: const ValueKey('opp-edit-slots'),
                    label: 'SLOTS',
                    done: _rowDone(_RequiredField.slots),
                    value: _slots.isEmpty
                        ? null
                        : '${_slots.length} slot${_slots.length == 1 ? '' : 's'}',
                    placeholder: _isPrivate
                        ? 'Add a slot with a fee'
                        : 'Add a slot',
                    sub: _slots.isEmpty
                        ? null
                        : _slots
                              .map(
                                (slot) =>
                                    '${slot.role.wireValue} ${Money(slot.input.guaranteeMinor).label}',
                              )
                              .join(' · '),
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
                    key: const ValueKey('opp-edit-details-toggle'),
                    label: 'DETAILS · OPTIONAL',
                    sub:
                        'Style · Age · Description · Equipment · Requirements · '
                        '${_isPrivate ? 'Expected guests' : 'Expected attendance'}',
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
                    const EpSectionHeader(label: 'TICKETING'),
                    ..._ticketingControls(
                      enabled: enabled,
                      canManage: canManage,
                      ticketFieldsEnabled: ticketFieldsEnabled,
                    ),
                  ],
                  const EpSectionHeader(label: 'VISIBILITY'),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final visibility in OpportunityVisibility.values)
                        EpChip(
                          key: ValueKey(
                            'opp-edit-visibility-${visibility == OpportunityVisibility.publicListing ? 'public' : 'invite'}',
                          ),
                          label:
                              visibility == OpportunityVisibility.publicListing
                              ? 'PUBLIC'
                              : 'INVITE ONLY',
                          active: _visibility == visibility,
                          onTap: enabled
                              ? () => _changed(() => _visibility = visibility)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                  if (_editable && canManage)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: EpPill(
                        key: const ValueKey('opp-edit-save'),
                        label: draft ? 'Save draft' : 'Save changes',
                        variant: EpPillVariant.outline,
                        size: EpPillSize.chip,
                        onPressed: enabled ? _save : null,
                      ),
                    ),
                  if (canManage &&
                      _savedId != null &&
                      _status != OpportunityStatus.cancelled &&
                      _status != OpportunityStatus.completed) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey(
                          draft ? 'opp-edit-delete' : 'opp-edit-cancel',
                        ),
                        onPressed: _busy ? null : _deleteOrCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: palette.destructive,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: EpMonoText(
                          draft ? 'Delete draft' : 'Cancel opportunity',
                          color: _busy
                              ? palette.contentDisabled
                              : palette.destructive,
                        ),
                      ),
                    ),
                  ],
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
          if (showFooter)
            Positioned(
              left: 0,
              right: 0,
              bottom: EpLayout.isDesktop(context) ? 0 : 67,
              child: EpBottomCta(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EpEyebrow(
                      needs.isEmpty
                          ? 'Ready'
                          : 'Still needs ${needs.join(' + ')}',
                      key: const ValueKey('opp-edit-missing'),
                    ),
                    const SizedBox(height: 12),
                    EpPill(
                      key: ValueKey(switch (_status) {
                        OpportunityStatus.draft => 'opp-edit-open',
                        OpportunityStatus.open => 'opp-edit-close',
                        _ => 'opp-edit-reopen',
                      }),
                      label: waitingForVenueApproval
                          ? 'WAITING FOR VENUE APPROVAL'
                          : switch (_status) {
                              OpportunityStatus.draft =>
                                'OPEN FOR APPLICATIONS',
                              OpportunityStatus.open => 'CLOSE APPLICATIONS',
                              _ => 'REOPEN',
                            },
                      variant: EpPillVariant.primary,
                      size: EpPillSize.large,
                      expand: true,
                      onPressed:
                          !waitingForVenueApproval &&
                              enabled &&
                              _savedId != null &&
                              (!draft || needs.isEmpty)
                          ? _transition
                          : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

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

  List<Widget> _ticketingControls({
    required bool enabled,
    required bool canManage,
    required bool ticketFieldsEnabled,
  }) {
    final caption = Theme.of(context).textTheme.epCaption;
    return [
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final ticketing in [
            OpportunityTicketing.none,
            OpportunityTicketing.rsvp,
            OpportunityTicketing.external,
            OpportunityTicketing.paid,
          ])
            EpChip(
              key: ValueKey('opp-edit-ticketing-${ticketing.wireValue}'),
              label: ticketing.wireValue,
              active: _ticketing == ticketing,
              onTap:
                  enabled &&
                      (ticketing != OpportunityTicketing.paid ||
                          _stripeChargesEnabled)
                  ? () => _changed(() => _ticketing = ticketing)
                  : null,
            ),
        ],
      ),
      if (!_stripeChargesEnabled) ...[
        const SizedBox(height: 8),
        Text('Connect Stripe in SETTINGS to sell tickets', style: caption),
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

/// One line of the form: a filled check or an empty ring for required rows,
/// the row's eyebrow, its value (or an accent invitation when empty) and a
/// chevron that folds the row's controls open underneath. The TITLE row
/// passes its inline field as [child] instead of a value.
class _FormRow extends StatelessWidget {
  const _FormRow({
    super.key,
    this.label,
    this.done,
    this.value,
    this.placeholder,
    this.sub,
    this.expanded,
    this.onTap,
    this.child,
  });

  final String? label;
  final bool? done;
  final String? value;
  final String? placeholder;
  final String? sub;
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
          if (done != null) ...[
            if (done!)
              Icon(Icons.check, size: 16, color: palette.accent)
            else
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.accent),
                ),
              ),
            const SizedBox(width: 12),
          ],
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
          if (onTap != null) ...[
            const SizedBox(width: 12),
            Icon(
              expanded == true ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: palette.contentSecondary,
            ),
          ],
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
            child: InkWell(onTap: onTap, child: content),
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

String _dateLabel(BuildContext context, DateTime? date) => date == null
    ? 'CHOOSE'
    : MaterialLocalizations.of(context).formatMediumDate(date);

String _extractErrorMessage(Object error) =>
    serverErrorMessage(error) ?? error.toString();
