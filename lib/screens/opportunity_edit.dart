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
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import 'private_locations.dart';

class OpportunityEditScreen extends StatefulWidget {
  const OpportunityEditScreen({super.key, required this.opportunityId});

  final String opportunityId;

  @override
  State<OpportunityEditScreen> createState() => _OpportunityEditScreenState();
}

class _OpportunityEditScreenState extends State<OpportunityEditScreen> {
  final _scroll = ScrollController();
  final _eventForm = GlobalKey<EpFormState>();
  int _step = 0;
  bool _attempted = false;
  bool get _guided => widget.opportunityId == 'new';
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

  List<String> get _saveNeeds => [
    if (_title.text.trim().isEmpty) 'title',
    if (_isPrivate) ...[
      if (_privateLocationId == null) 'location',
    ] else ...[
      if (_venueId == null) 'venue',
    ],
    if (_startsAt == null) 'date',
    if (_isPrivate) ...[
      if (!_validDeadline) 'deadline',
      if (_slots.isEmpty ||
          _slots.any((slot) => slot.input.guaranteeMinor <= 0))
        'a fee for every slot',
    ],
    if (_ticketing == OpportunityTicketing.paid) ...[
      if (_ticketPriceError != null) 'ticket price',
      if (_ticketCapacityError != null) 'ticket capacity',
    ],
  ];

  List<String> get _openNeeds => [
    ..._saveNeeds,
    if (_slots.isEmpty) 'at least one slot',
    if (!_isPrivate && !_validDeadline) 'deadline before start',
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
    _load();
  }

  Future<void> _load() async {
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
    setState(() => _error = 'Needs: ${needs.join(', ')}');
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
      if (_ticketPriceError != null) 'ticket price',
      if (_ticketCapacityError != null) 'ticket capacity',
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
      _showNeeds(['deadline before start']);
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
        child: Material(
          color: Colors.transparent,
          child: _InviteBandSearch(
            repository: repository,
            invitedIds: Set.of(_invitedIds),
            onSelected: _inviteBand,
          ),
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
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel opportunity'),
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isVenueOperator = app.currentIsVenueOperator;
    final canManage = app.canManageOrganization(app.organizationId);
    final enabled = canManage && _editable && !_busy;
    final ticketFieldsEnabled =
        enabled || (canManage && !_busy && _ticketingEditable);
    final draft = _status == OpportunityStatus.draft;
    final slotsEnabled = enabled && draft;
    final needs = _openNeeds;
    final venueApprovalLocked =
        !_isPrivate &&
        !isVenueOperator &&
        (_venueConsent?.status == VenueConsentStatus.pending ||
            _venueConsent?.status == VenueConsentStatus.granted);
    final venueEnabled = slotsEnabled && !venueApprovalLocked;
    final whenEnabled = enabled && !venueApprovalLocked;
    final waitingForVenueApproval =
        !isVenueOperator &&
        !_isPrivate &&
        draft &&
        _venueId != null &&
        _venueConsent?.status != VenueConsentStatus.granted;
    final venueApproval = _venueApprovalStatus(_venueConsent?.status);
    final venueQuery = _venueSearch.text.trim().toLowerCase();
    final matchingVenues = !_isPrivate && !isVenueOperator
        ? app.venues.where((venue) {
            return venue.verified &&
                venue.managedByOrganizationId != null &&
                (venueQuery.isEmpty ||
                    venue.name.toLowerCase().contains(venueQuery) ||
                    venue.area.toLowerCase().contains(venueQuery));
          })
        : const <Venue>[];

    final sections = <({String title, String summary, Widget child})>[
      (
        title: 'Event',
        summary: '${_title.text} · ${_dateLabel(context, _date)}',
        child: EpForm(
          key: _eventForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EpLabeledField(
                fieldKey: const ValueKey('opp-edit-title'),
                label: 'Title',
                hint: 'Give this night a name',
                controller: _title,
                required: true,
                enabled: enabled,
                onChanged: _textChanged,
              ),
              if (_isPrivate) ...[
                if (_privateLocations.isEmpty)
                  EpButton(
                    'Add a location',
                    key: const Key('opp-add-location'),
                    kind: EpButtonKind.outline,
                    onTap: slotsEnabled ? _addPrivateLocation : null,
                  )
                else
                  EpSelectionField<String>(
                    key: const Key('opp-edit-location'),
                    label: 'Location',
                    options: [
                      for (final location in _privateLocations)
                        (value: location.id, label: location.label),
                    ],
                    selected: {?_privateLocationId},
                    onChanged: slotsEnabled
                        ? (values) =>
                              _changed(() => _privateLocationId = values.single)
                        : null,
                  ),
                const SizedBox(height: 8),
                Text(
                  'Artists see the area only. The exact address is shared after the deposit.',
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ] else
                EpSelectionField<String>(
                  key: const Key('opp-edit-venue'),
                  label: 'Venue',
                  options: [
                    for (final venue
                        in isVenueOperator ? _venues : matchingVenues)
                      (value: venue.id, label: '${venue.name} · ${venue.area}'),
                  ],
                  selected: {?_venueId},
                  onChanged: venueEnabled
                      ? (values) => _changed(() => _venueId = values.single)
                      : null,
                ),
              const SectionBar.form(label: 'When'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey('opp-edit-date'),
                    onPressed: whenEnabled ? _pickDate : null,
                    child: Text('DATE · ${_dateLabel(context, _date)}'),
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
        ),
      ),
      (
        title: 'Artist slots',
        summary: '${_slots.length} slots · ${_genres.join(', ')}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionBar.form(label: 'Slots', count: _slots.length),
            if (!draft)
              Text(
                'Slots are locked once applications are open.',
                style: Theme.of(context).textTheme.epCaption,
              ),
            for (var i = 0; i < _slots.length; i++)
              _slotFields(i, slotsEnabled),
            OutlinedButton.icon(
              key: const ValueKey('opp-edit-slot-add'),
              onPressed: slotsEnabled && _slots.length < 8
                  ? () => _changed(() => _slots.add(_SlotDraft()))
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Add slot'),
            ),
            const SizedBox(height: 20),
            EpSelectionField<String>(
              label: 'Genres',
              multiple: true,
              maxSelected: 5,
              options: [
                for (final genre in {...kGenres, ..._genres})
                  (value: genre, label: genre),
              ],
              selected: _genres,
              onChanged: enabled
                  ? (values) => _changed(() {
                      _genres.clear();
                      _genres.addAll(values);
                    })
                  : null,
            ),
          ],
        ),
      ),
      (
        title: 'Details',
        summary: _age.label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const FieldLabel('AGE'),
            Wrap(
              spacing: 7,
              children: [
                for (final age in AgeRequirement.values)
                  EpChip(
                    multiple: false,
                    key: ValueKey('opp-edit-age-${age.wireValue}'),
                    label: age.label,
                    active: _age == age,
                    onTap: enabled ? () => _changed(() => _age = age) : null,
                  ),
              ],
            ),
            const SectionBar.form(label: 'Details'),
            EpLabeledField(
              fieldKey: const ValueKey('opp-edit-desc'),
              label: 'Description',
              hint: 'Tell artists about the show',
              controller: _description,
              minLines: 3,
              maxLines: 6,
              enabled: enabled,
              onChanged: _textChanged,
            ),
            const SizedBox(height: EpLayout.fieldGap),
            EpDisclosure(
              title: 'Logistics',
              summary: 'Optional equipment, requirements and attendance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EpLabeledField(
                    fieldKey: const ValueKey('opp-edit-equipment'),
                    label: 'Equipment',
                    hint: 'Backline and equipment provided',
                    controller: _equipment,
                    enabled: enabled,
                    onChanged: _textChanged,
                  ),
                  const SizedBox(height: EpLayout.fieldGap),
                  EpLabeledField(
                    fieldKey: const ValueKey('opp-edit-requirements'),
                    label: 'Requirements',
                    hint: 'What artists should bring or know',
                    controller: _requirements,
                    enabled: enabled,
                    onChanged: _textChanged,
                  ),
                  const SizedBox(height: EpLayout.fieldGap),
                  EpLabeledField(
                    fieldKey: const ValueKey('opp-edit-attendance'),
                    label: _isPrivate
                        ? 'EXPECTED GUESTS'
                        : 'EXPECTED ATTENDANCE',
                    hint: 'Optional',
                    controller: _attendance,
                    keyboardType: TextInputType.number,
                    enabled: enabled,
                    onChanged: _textChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      (
        title: 'Access',
        summary:
            '${_visibility == OpportunityVisibility.publicListing ? 'Public' : 'Invite only'} · ${_invitedIds.length} invitations',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              key: const ValueKey('opp-edit-deadline'),
              onPressed: whenEnabled ? () => _pickDate(deadline: true) : null,
              child: Text('DEADLINE · ${_dateLabel(context, _deadline)}'),
            ),
            if (!_isPrivate) ...[
              const SectionBar.form(label: 'Ticketing'),
              Wrap(
                spacing: 7,
                children: [
                  for (final ticketing in [
                    OpportunityTicketing.none,
                    OpportunityTicketing.rsvp,
                    OpportunityTicketing.external,
                    OpportunityTicketing.paid,
                  ])
                    EpChip(
                      multiple: false,
                      key: ValueKey(
                        'opp-edit-ticketing-${ticketing.wireValue}',
                      ),
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
              if (!_stripeChargesEnabled)
                Text(
                  'Connect Stripe in SETTINGS to sell tickets',
                  style: Theme.of(context).textTheme.epCaption,
                ),
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
                    errorText: _attempted || !_guided
                        ? _ticketPriceError
                        : null,
                  ),
                  second: EpLabeledField(
                    fieldKey: const ValueKey('opp-edit-ticket-capacity'),
                    label: 'Capacity',
                    hint: '100',
                    controller: _ticketCapacity,
                    keyboardType: TextInputType.number,
                    enabled: ticketFieldsEnabled,
                    onChanged: _textChanged,
                    errorText: _attempted || !_guided
                        ? _ticketCapacityError
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _ticketingFeeCaption,
                  style: Theme.of(context).textTheme.epCaption,
                ),
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
                  label: 'External ticket url',
                  hint: 'https://',
                  controller: _externalUrl,
                  keyboardType: TextInputType.url,
                  enabled: enabled,
                  onChanged: _textChanged,
                ),
              ],
            ],
            const SectionBar.form(label: 'Visibility'),
            Wrap(
              spacing: 7,
              children: [
                for (final visibility in OpportunityVisibility.values)
                  EpChip(
                    multiple: false,
                    key: ValueKey(
                      'opp-edit-visibility-${visibility == OpportunityVisibility.publicListing ? 'public' : 'invite'}',
                    ),
                    label: visibility == OpportunityVisibility.publicListing
                        ? 'PUBLIC'
                        : 'INVITE ONLY',
                    active: _visibility == visibility,
                    onTap: enabled
                        ? () => _changed(() => _visibility = visibility)
                        : null,
                  ),
              ],
            ),
            const SectionBar.form(label: 'Invite bands'),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final id in _invitedIds)
                  EpChip(
                    multiple: false,
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
              label: const Text('Invite a band'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      (
        title: 'Review',
        summary: _isPrivate || isVenueOperator
            ? 'Requirements and publication'
            : venueApproval.label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_title.text, style: Theme.of(context).textTheme.titleLarge),
            Text(
              '${_dateLabel(context, _date)} · Doors ${_doors.format(context)} · Start ${_start.format(context)}',
            ),
            Text('${_slots.length} artist slots · ${_age.label}'),
            Text('Applications close ${_dateLabel(context, _deadline)}'),
            const SizedBox(height: 20),
            Text(
              needs.isEmpty
                  ? 'Ready to open applications after saving.'
                  : 'Complete ${needs.join(', ')} before opening applications.',
              key: const ValueKey('opp-edit-missing'),
            ),
            if (!_isPrivate && !isVenueOperator && _savedId != null) ...[
              const SectionBar.form(label: 'Venue approval'),
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
        ),
      ),
    ];
    return Scaffold(
      backgroundColor: context.epColors.background,
      body: EpFormLayout(
        body: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleIconButton(onTap: _busy ? null : _close),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _savedTitle.trim().isEmpty
                          ? (_isPrivate
                                ? 'Create private request'
                                : 'Create opportunity')
                          : _savedTitle,
                      style: Theme.of(context).textTheme.epFormHeading,
                    ),
                  ),
                  if (_guided && _step < 4)
                    TextButton(
                      key: const ValueKey('opp-edit-save'),
                      onPressed: enabled ? _save : null,
                      child: const Text('Save draft'),
                    ),
                  if (_savedId != null) ...[
                    const SizedBox(width: 8),
                    StatusPill(label: _status.wireValue.replaceAll('_', ' ')),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Artists apply to slots. Fans never see this until it is confirmed.',
                style: Theme.of(context).textTheme.epCaption,
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_loadError != null) ...[
                Text(_loadError!),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ] else ...[
                if (_guided)
                  EpFormSteps(
                    labels: [for (final section in sections) section.title],
                    current: _step,
                    onBackToStep: _busy ? null : _showStep,
                  ),
                for (var i = 0; i < sections.length; i++)
                  if (_guided)
                    EpFormStep(active: _step == i, child: sections[i].child)
                  else
                    EpDisclosure(
                      title: sections[i].title,
                      summary: sections[i].summary,
                      initiallyExpanded: i == 0,
                      child: sections[i].child,
                    ),
                InlineFormFeedback(
                  error: _attempted ? _stepError ?? _error : _error,
                  success: _success,
                  errorKey: const ValueKey('opp-edit-feedback'),
                ),
                if ((!_guided || _step == 4) &&
                    canManage &&
                    _status != OpportunityStatus.cancelled &&
                    _status != OpportunityStatus.completed)
                  DangerZone(
                    key: ValueKey(
                      draft ? 'opp-edit-delete' : 'opp-edit-cancel',
                    ),
                    label: draft ? 'Delete draft' : 'Cancel opportunity',
                    consequence: draft
                        ? 'Permanently remove this draft.'
                        : 'Cancel this opportunity and its applications.',
                    onPressed: _busy ? null : _deleteOrCancel,
                  ),
              ],
            ],
          ),
        ),
        footer: _loading || _loadError != null || !_editable || !canManage
            ? const SizedBox.shrink()
            : _guided && _step < 4
            ? StickyActionBar(
                primaryLabel: 'Continue',
                onPrimary: _busy ? null : _continue,
                secondaryLabel: _step == 0 ? null : 'Back',
                onSecondary: _busy ? null : () => _showStep(_step - 1),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_guided)
                    TextButton(
                      onPressed: _busy ? null : () => _showStep(3),
                      child: const Text('Back to access'),
                    ),
                  StickyActionBar(
                    key: ValueKey(switch (_status) {
                      OpportunityStatus.draft => 'opp-edit-open',
                      OpportunityStatus.open => 'opp-edit-close',
                      _ => 'opp-edit-reopen',
                    }),
                    primaryLabel: waitingForVenueApproval
                        ? 'WAITING FOR VENUE APPROVAL'
                        : switch (_status) {
                            OpportunityStatus.draft => 'OPEN FOR APPLICATIONS',
                            OpportunityStatus.open => 'CLOSE APPLICATIONS',
                            _ => 'REOPEN',
                          },
                    onPrimary:
                        !waitingForVenueApproval &&
                            enabled &&
                            _savedId != null &&
                            (!draft || needs.isEmpty)
                        ? _transition
                        : null,
                    secondaryKey: const ValueKey('opp-edit-save'),
                    secondaryLabel: draft ? 'SAVE DRAFT' : 'SAVE CHANGES',
                    onSecondary: enabled ? _save : null,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _addPrivateLocation() async {
    // Keep this editor mounted while the location is created so the request's
    // title, timing and other unsaved fields survive both Cancel and Save.
    final app = context.read<AppState>();
    String? createdId;
    await showEpSheet(
      context,
      (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .9,
        child: PrivateLocationEditScreen(
          locationId: 'new',
          onCancel: () => Navigator.pop(sheetContext),
          onSaved: (id) {
            createdId = id;
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
    if (!mounted || createdId == null) return;
    try {
      final locations = await app.repository.privateLocationsFor(
        app.organizationId,
      );
      if (!mounted) return;
      _changed(() {
        _privateLocations = locations;
        _privateLocationId = createdId;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _extractErrorMessage(error));
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    if ((_dirty || _pendingInvites.isNotEmpty) &&
        !await confirmDiscardForm(context)) {
      return;
    }
    if (mounted) context.read<AppState>().back();
  }

  void _showStep(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _attempted = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String? get _stepError => switch (_step) {
    0 when _title.text.trim().isEmpty => 'Enter a title.',
    0 when _isPrivate ? _privateLocationId == null : _venueId == null =>
      'Choose ${_isPrivate ? 'a location' : 'a venue'}.',
    0 when _date == null => 'Choose the event date.',
    1 when _slots.isEmpty => 'Add at least one artist slot.',
    1 when _isPrivate && _slots.any((slot) => slot.input.guaranteeMinor <= 0) =>
      'Enter a fee for every artist slot.',
    3 when !_validDeadline =>
      'Choose an application deadline before the event starts.',
    3
        when _ticketing == OpportunityTicketing.paid &&
            _ticketPriceError != null =>
      _ticketPriceError,
    3
        when _ticketing == OpportunityTicketing.paid &&
            _ticketCapacityError != null =>
      _ticketCapacityError,
    _ => null,
  };

  void _continue() {
    setState(() => _attempted = true);
    if (_step == 0 && _eventForm.currentState?.validate() != true) return;
    if (_stepError != null) {
      revealFormFeedback(this, _scroll);
      return;
    }
    _showStep(_step + 1);
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
                  multiple: false,
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
                  label: 'Required',
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
            label: 'Message',
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
