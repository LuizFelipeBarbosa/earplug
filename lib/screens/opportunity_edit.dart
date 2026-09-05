import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../genres.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/band_identity_editor.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

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
  DateTime? _date;
  TimeOfDay _doors = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay _start = const TimeOfDay(hour: 21, minute: 0);
  DateTime? _deadline;
  bool _deadlineTouched = false;
  AgeRequirement _age = AgeRequirement.allAges;
  OpportunityTicketing _ticketing = OpportunityTicketing.rsvp;
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

  DateTime? _atTime(TimeOfDay time) {
    final date = _date;
    return date == null
        ? null
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime? get _startsAt => _atTime(_start);
  bool get _validDeadline =>
      _deadline != null && _startsAt != null && _deadline!.isBefore(_startsAt!);

  List<String> get _saveNeeds => [
    if (_title.text.trim().isEmpty) 'title',
    if (_venueId == null) 'venue',
    if (_startsAt == null) 'date',
  ];

  List<String> get _openNeeds => [
    ..._saveNeeds,
    if (_slots.isEmpty) 'at least one slot',
    if (!_validDeadline) 'deadline before start',
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
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final key = _loadedKey;
    final organizationId = app.organizationId;
    final id = widget.opportunityId;
    setState(() {
      _loading = true;
      _loadError = null;
    });
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
      final bands = <String, Band>{};
      for (final bandId in opportunity?.invitedBandIds ?? <String>[]) {
        final band = await app.repository.band(bandId);
        if (band != null) bands[bandId] = band;
      }
      if (!mounted || key != _loadedKey) return;
      setState(() {
        _venues = dashboard.venues;
        _bands
          ..clear()
          ..addAll(bands);
        _populate(opportunity);
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

  void _populate(Opportunity? opportunity) {
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
    _venueId = opportunity?.venueId;
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
    _ticketing = opportunity?.ticketing ?? OpportunityTicketing.rsvp;
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
        if (!_deadlineTouched && _deadline == null) {
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
    if (_savedId == null) {
      _saved = await app.repository.createOpportunity(
        organizationId: app.organizationId,
        title: title,
        venueId: _venueId!,
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
        ticketing: _ticketing,
        externalUrl: _externalUrl.text.trim(),
        slots: slots,
      );
      _revision = 1;
    } else {
      _revision = await app.repository.updateOpportunity(
        opportunityId: _savedId!,
        expectedRevision: _revision,
        title: title,
        venueId: _venueId,
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
        ticketing: _ticketing,
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canManage = app.canManageOrganization(app.organizationId);
    final enabled = canManage && _editable && !_busy;
    final draft = _status == OpportunityStatus.draft;
    final slotsEnabled = enabled && draft;
    final needs = _openNeeds;

    return Scaffold(
      backgroundColor: context.epColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                16,
                headerTopPad(context),
                16,
                tabBarClearance + 112 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Row(
                  children: [
                    CircleIconButton(onTap: app.back),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _savedTitle.trim().isEmpty
                            ? 'NEW OPPORTUNITY'
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
                  TextButton(onPressed: _load, child: const Text('RETRY')),
                ] else ...[
                  BandIdentityTextField(
                    fieldKey: const ValueKey('opp-edit-title'),
                    label: 'TITLE',
                    hint: 'Give this night a name',
                    controller: _title,
                    required: true,
                    enabled: enabled,
                    onChanged: _textChanged,
                  ),
                  const SectionBar(label: 'VENUE'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final venue in _venues)
                        EpChip(
                          key: ValueKey('opp-edit-venue-${venue.id}'),
                          label: venue.name,
                          active: _venueId == venue.id,
                          onTap: slotsEnabled
                              ? () => _changed(() => _venueId = venue.id)
                              : null,
                        ),
                    ],
                  ),
                  const SectionBar(label: 'WHEN'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('opp-edit-date'),
                        onPressed: enabled ? _pickDate : null,
                        child: Text('DATE · ${_dateLabel(context, _date)}'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('opp-edit-doors'),
                        onPressed: enabled
                            ? () => _pickTime(doors: true)
                            : null,
                        child: Text('DOORS · ${_doors.format(context)}'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('opp-edit-start'),
                        onPressed: enabled
                            ? () => _pickTime(doors: false)
                            : null,
                        child: Text('START · ${_start.format(context)}'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('opp-edit-deadline'),
                        onPressed: enabled
                            ? () => _pickDate(deadline: true)
                            : null,
                        child: Text(
                          'DEADLINE · ${_dateLabel(context, _deadline)}',
                        ),
                      ),
                    ],
                  ),
                  SectionBar(label: 'SLOTS', count: _slots.length),
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
                    label: const Text('ADD SLOT'),
                  ),
                  const SectionBar(label: 'STYLE'),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final genre in kGenres)
                        EpChip(
                          key: ValueKey('opp-edit-genre-$genre'),
                          label: genre,
                          active: _genres.contains(genre),
                          onTap:
                              enabled &&
                                  (_genres.length < 5 ||
                                      _genres.contains(genre))
                              ? () => _changed(() {
                                  if (!_genres.remove(genre)) {
                                    _genres.add(genre);
                                  }
                                })
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('AGE'),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final age in AgeRequirement.values)
                        EpChip(
                          key: ValueKey('opp-edit-age-${age.wireValue}'),
                          label: age.label,
                          active: _age == age,
                          onTap: enabled
                              ? () => _changed(() => _age = age)
                              : null,
                        ),
                    ],
                  ),
                  const SectionBar(label: 'DETAILS'),
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
                  const SizedBox(height: 12),
                  EpLabeledField(
                    fieldKey: const ValueKey('opp-edit-equipment'),
                    label: 'EQUIPMENT',
                    hint: 'Backline and equipment provided',
                    controller: _equipment,
                    enabled: enabled,
                    onChanged: _textChanged,
                  ),
                  const SizedBox(height: 12),
                  EpLabeledField(
                    fieldKey: const ValueKey('opp-edit-requirements'),
                    label: 'REQUIREMENTS',
                    hint: 'What artists should bring or know',
                    controller: _requirements,
                    enabled: enabled,
                    onChanged: _textChanged,
                  ),
                  const SizedBox(height: 12),
                  EpLabeledField(
                    fieldKey: const ValueKey('opp-edit-attendance'),
                    label: 'EXPECTED ATTENDANCE',
                    hint: 'Optional',
                    controller: _attendance,
                    keyboardType: TextInputType.number,
                    enabled: enabled,
                    onChanged: _textChanged,
                  ),
                  const SectionBar(label: 'TICKETING'),
                  Wrap(
                    spacing: 7,
                    children: [
                      for (final ticketing in [
                        OpportunityTicketing.none,
                        OpportunityTicketing.rsvp,
                        OpportunityTicketing.external,
                      ])
                        EpChip(
                          key: ValueKey(
                            'opp-edit-ticketing-${ticketing.wireValue}',
                          ),
                          label: ticketing.wireValue,
                          active: _ticketing == ticketing,
                          onTap: enabled
                              ? () => _changed(() => _ticketing = ticketing)
                              : null,
                        ),
                    ],
                  ),
                  if (_ticketing == OpportunityTicketing.external)
                    EpLabeledField(
                      fieldKey: const ValueKey('opp-edit-external-url'),
                      label: 'EXTERNAL TICKET URL',
                      hint: 'https://',
                      controller: _externalUrl,
                      keyboardType: TextInputType.url,
                      enabled: enabled,
                      onChanged: _textChanged,
                    ),
                  const SectionBar(label: 'VISIBILITY'),
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
                  const SectionBar(label: 'INVITE BANDS'),
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
                  const SizedBox(height: 20),
                  InlineFormFeedback(
                    error: _error,
                    success: _success,
                    errorKey: const ValueKey('opp-edit-feedback'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    needs.isEmpty ? 'READY' : 'Needs: ${needs.join(', ')}',
                    key: const ValueKey('opp-edit-missing'),
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                  if (canManage &&
                      _status != OpportunityStatus.cancelled &&
                      _status != OpportunityStatus.completed) ...[
                    const SizedBox(height: 24),
                    DangerZone(
                      key: ValueKey(
                        draft ? 'opp-edit-delete' : 'opp-edit-cancel',
                      ),
                      label: draft ? 'DELETE DRAFT' : 'CANCEL OPPORTUNITY',
                      consequence: draft
                          ? 'Permanently remove this draft.'
                          : 'Cancel this opportunity and its applications.',
                      onPressed: _busy ? null : _deleteOrCancel,
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (!_loading && _loadError == null && _editable && canManage)
            Positioned(
              left: 0,
              right: 0,
              bottom: 67,
              child: StickyActionBar(
                key: ValueKey(switch (_status) {
                  OpportunityStatus.draft => 'opp-edit-open',
                  OpportunityStatus.open => 'opp-edit-close',
                  _ => 'opp-edit-reopen',
                }),
                primaryLabel: switch (_status) {
                  OpportunityStatus.draft => 'OPEN FOR APPLICATIONS',
                  OpportunityStatus.open => 'CLOSE APPLICATIONS',
                  _ => 'REOPEN',
                },
                onPrimary:
                    enabled && _savedId != null && (!draft || needs.isEmpty)
                    ? _transition
                    : null,
                secondaryKey: const ValueKey('opp-edit-save'),
                secondaryLabel: draft ? 'SAVE DRAFT' : 'SAVE CHANGES',
                onSecondary: enabled ? _save : null,
              ),
            ),
        ],
      ),
    );
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: EpLabeledField(
                  fieldKey: ValueKey('opp-edit-slot-$index-guarantee'),
                  label: 'GUARANTEE (\$)',
                  hint: '0',
                  controller: slot.guarantee,
                  keyboardType: TextInputType.number,
                  enabled: enabled,
                  onChanged: _textChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: EpLabeledField(
                  fieldKey: ValueKey('opp-edit-slot-$index-length'),
                  label: 'SET (MINUTES)',
                  hint: 'Optional',
                  controller: slot.length,
                  keyboardType: TextInputType.number,
                  enabled: enabled,
                  onChanged: _textChanged,
                ),
              ),
            ],
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
          decoration: sheetInput(context, 'Search EarPlug bands'),
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

String _extractErrorMessage(Object error) {
  final text = error.toString();
  const prefix = 'Uncaught Error:';
  final index = text.lastIndexOf(prefix);
  if (index >= 0) return text.substring(index + prefix.length).trim();
  return text
      .replaceFirst(RegExp(r'^(Bad state: |Exception: |ConvexError: )'), '')
      .trim();
}
