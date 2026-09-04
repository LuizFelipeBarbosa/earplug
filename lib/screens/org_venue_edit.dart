import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/venue_location_editor.dart';

class OrgVenueEditScreen extends StatefulWidget {
  const OrgVenueEditScreen({super.key, required this.venueId});

  final String venueId;

  @override
  State<OrgVenueEditScreen> createState() => _OrgVenueEditScreenState();
}

class _OrgVenueEditScreenState extends State<OrgVenueEditScreen> {
  final _scrollController = ScrollController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _publicCapacity = TextEditingController();
  final _loadInNotes = TextEditingController();

  Venue? _venue;
  VenueType _venueType = VenueType.other;
  VenueLocationDraft _location = const VenueLocationDraft();
  AddressDisclosure _disclosure = AddressDisclosure.onTicket;
  int? _privateCapacity;

  String _loadedName = '';
  String _loadedDescription = '';
  String _loadedPublicCapacity = '';
  VenueType _loadedVenueType = VenueType.other;
  String _loadedAddress = '';
  LatLng? _loadedPin;
  String _loadedLoadInNotes = '';

  String? _loadedKey;
  String? _loadError;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _savingDisclosure = false;
  bool _saved = false;
  int _locationEditorRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final organizationId = context.read<AppState>().organizationId;
    final loadKey = '$organizationId:${widget.venueId}';
    if (_loadedKey == loadKey) return;
    _loadedKey = loadKey;
    _venue = null;
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _name.dispose();
    _description.dispose();
    _publicCapacity.dispose();
    _loadInNotes.dispose();
    super.dispose();
  }

  Future<({Venue venue, VenuePrivateDetails? details})> _fetchVenue(
    String organizationId,
  ) async {
    final repository = context.read<AppState>().repository;
    final dashboard = await repository.organizationDashboard(organizationId);
    Venue? venue;
    for (final candidate in dashboard.venues) {
      if (candidate.id == widget.venueId) {
        venue = candidate;
        break;
      }
    }
    if (venue == null) throw const _VenueNotFound();
    final details = await repository.venuePrivateDetails(widget.venueId);
    return (venue: venue, details: details);
  }

  bool _requestIsCurrent(String organizationId) {
    if (!mounted) return false;
    final app = context.read<AppState>();
    return app.organizationId == organizationId &&
        _loadedKey == '$organizationId:${widget.venueId}';
  }

  void _seed(({Venue venue, VenuePrivateDetails? details}) loaded) {
    final venue = loaded.venue;
    final details = loaded.details;
    final name = venue.name;
    final description = venue.description ?? '';
    final publicCapacity = venue.capacityPublic?.toString() ?? '';
    final venueType = venue.venueType ?? VenueType.other;
    final address = details?.addr ?? '';
    final loadInNotes = details?.loadInNotes ?? '';

    _venue = venue;
    _name.text = name;
    _description.text = description;
    _publicCapacity.text = publicCapacity;
    _loadInNotes.text = loadInNotes;
    _venueType = venueType;
    _disclosure = venue.disclosure;
    _privateCapacity = details?.capacity;
    _location = VenueLocationDraft(
      address: address,
      area: venue.neighborhood ?? venue.city ?? '',
      pin: details?.point,
    );

    _loadedName = name;
    _loadedDescription = description;
    _loadedPublicCapacity = publicCapacity;
    _loadedVenueType = venueType;
    _loadedAddress = address;
    _loadedPin = details?.point;
    _loadedLoadInNotes = loadInNotes;
    _locationEditorRevision++;
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loaded = await _fetchVenue(organizationId);
      if (!_requestIsCurrent(organizationId)) return;
      setState(() {
        _seed(loaded);
        _loading = false;
      });
    } on _VenueNotFound {
      if (!_requestIsCurrent(organizationId)) return;
      setState(() {
        _loadError = 'This venue is not connected to this organization.';
        _loading = false;
      });
    } on Object {
      if (!_requestIsCurrent(organizationId)) return;
      setState(() {
        _loadError = 'Could not load venue details.';
        _loading = false;
      });
    }
  }

  ({bool publicProfile, bool privateDetails}) get _changesSinceLoad => (
    publicProfile:
        _name.text != _loadedName ||
        _description.text != _loadedDescription ||
        _venueType != _loadedVenueType ||
        _publicCapacity.text != _loadedPublicCapacity,
    privateDetails:
        _location.address != _loadedAddress ||
        _location.pin != _loadedPin ||
        _loadInNotes.text != _loadedLoadInNotes,
  );

  void _draftChanged([Object? _]) {
    if (!_saved && _error == null) return;
    setState(() {
      _saved = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    if (_saving || !app.canManageOrganization(app.organizationId)) return;

    final organizationId = app.organizationId;
    final changes = _changesSinceLoad;
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      if (changes.publicProfile) {
        await app.repository.updateVenueProfile(
          venueId: widget.venueId,
          name: _name.text.trim(),
          description: _description.text.trim(),
          venueType: _venueType,
          capacityPublic: int.tryParse(_publicCapacity.text.trim()),
        );
      }
      if (changes.privateDetails && _location.pin != null) {
        await app.repository.updateVenuePrivateDetails(
          venueId: widget.venueId,
          addr: _location.address.trim(),
          point: _location.pin!,
          loadInNotes: _loadInNotes.text.trim(),
          capacity: _privateCapacity,
        );
      }

      if (changes.publicProfile ||
          (changes.privateDetails && _location.pin != null)) {
        final loaded = await _fetchVenue(organizationId);
        if (!_requestIsCurrent(organizationId)) return;
        setState(() => _seed(loaded));
      }
      if (!mounted) return;
      setState(() => _saved = true);
      revealFormFeedback(this, _scrollController);
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Changes could not be saved. Check your connection and retry.';
      });
      revealFormFeedback(this, _scrollController);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setDisclosure(bool disclosePublicly) async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    final isOwner =
        app.organizerRoleFor(organizationId) == OrganizationRole.owner;
    if (_savingDisclosure || !isOwner) return;

    final disclosure = disclosePublicly
        ? AddressDisclosure.public
        : AddressDisclosure.onTicket;
    setState(() {
      _savingDisclosure = true;
      _saved = false;
      _error = null;
    });
    try {
      await app.repository.setVenueAddressDisclosure(
        venueId: widget.venueId,
        disclosure: disclosure,
      );
      if (!_requestIsCurrent(organizationId)) return;
      setState(() => _disclosure = disclosure);

      final loaded = await _fetchVenue(organizationId);
      if (!_requestIsCurrent(organizationId)) return;
      setState(() {
        _seed(loaded);
        _saved = true;
      });
      revealFormFeedback(this, _scrollController);
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Address disclosure could not be saved. Please retry.';
      });
      revealFormFeedback(this, _scrollController);
    } finally {
      if (mounted) setState(() => _savingDisclosure = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venue = _venue;
    final canManage = app.canManageOrganization(app.organizationId);
    final isOwner =
        app.organizerRoleFor(app.organizationId) == OrganizationRole.owner;

    final listView = ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance + 112 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          _LoadError(message: _loadError!, onRetry: _load)
        else if (venue != null) ...[
          Row(
            children: [
              CircleIconButton(onTap: app.back),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  venue.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
            ],
          ),
          Text(
            '${venue.approx.label}${venue.verified ? ' · VERIFIED' : ''}',
            style: Theme.of(context).textTheme.epCaption,
          ),
          FormSection(
            title: 'Public',
            description:
                'These details appear anywhere EarPlug shows this venue.',
            boxed: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EpLabeledField(
                  label: 'NAME',
                  hint: 'Venue name',
                  fieldKey: const Key('org-venue-public-name'),
                  controller: _name,
                  required: true,
                  enabled: canManage,
                  onChanged: _draftChanged,
                ),
                const SizedBox(height: 12),
                EpLabeledField(
                  label: 'ABOUT',
                  hint: 'Tell artists and fans about the venue',
                  fieldKey: const Key('org-venue-public-description'),
                  controller: _description,
                  enabled: canManage,
                  minLines: 3,
                  maxLines: 5,
                  onChanged: _draftChanged,
                ),
                const SizedBox(height: 12),
                const FieldLabel('VENUE TYPE'),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final type in VenueType.values)
                      EpChip(
                        key: ValueKey('org-venue-type-${type.wireValue}'),
                        label: _venueTypeLabel(type),
                        active: _venueType == type,
                        onTap: canManage
                            ? () {
                                setState(() => _venueType = type);
                                _draftChanged();
                              }
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                EpLabeledField(
                  label: 'CAPACITY',
                  hint: 'Optional',
                  fieldKey: const Key('org-venue-public-capacity'),
                  controller: _publicCapacity,
                  enabled: canManage,
                  keyboardType: TextInputType.number,
                  onChanged: _draftChanged,
                ),
              ],
            ),
          ),
          FormSection(
            title: 'Location',
            description:
                'Fans see only the neighborhood until they hold a ticket.',
            boxed: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VenueLocationEditor(
                  key: ValueKey('org-venue-location-$_locationEditorRevision'),
                  keyPrefix: 'org-venue-private',
                  initial: _location,
                  onChanged: (draft) {
                    setState(() => _location = draft);
                    _draftChanged();
                  },
                  showNameField: false,
                  enabled: canManage,
                  initialCenter: _location.pin ?? venue.approx.centroid,
                  initialZoom: _location.pin == null ? 11.5 : 15,
                ),
                const SizedBox(height: 12),
                EpLabeledField(
                  label: 'LOAD-IN NOTES',
                  hint: 'Entrances, stairs, parking, or access notes',
                  fieldKey: const Key('org-venue-private-load-in'),
                  controller: _loadInNotes,
                  enabled: canManage,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: _draftChanged,
                ),
              ],
            ),
          ),
          if (isOwner)
            FormSection(
              title: 'Address disclosure',
              description: 'Control when the exact address becomes visible.',
              boxed: false,
              child: SwitchRow(
                key: const Key('org-venue-disclosure'),
                label: 'Show exact address publicly',
                value: _disclosure == AddressDisclosure.public,
                onChanged: isOwner && !_savingDisclosure
                    ? _setDisclosure
                    : null,
                caption:
                    'Otherwise the exact address is shared privately with booked artists and ticket holders, not shown publicly.',
              ),
            ),
          if (_error != null || _saved) ...[
            const SizedBox(height: 16),
            InlineFormFeedback(
              error: _error,
              success: _saved ? 'Changes saved.' : null,
              errorKey: const Key('org-venue-save-error'),
              successKey: const Key('org-venue-save-success'),
            ),
          ],
        ],
      ],
    );

    if (!canManage || venue == null || _loading || _loadError != null) {
      return listView;
    }
    return Stack(
      children: [
        Positioned.fill(child: listView),
        Positioned(
          left: 0,
          right: 0,
          bottom: 66,
          child: StickyActionBar(
            key: const Key('org-venue-save'),
            primaryLabel: _saving ? 'SAVING…' : 'SAVE CHANGES',
            onPrimary: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Column(
        children: [
          Text(message),
          const SizedBox(height: 12),
          EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
        ],
      ),
    );
  }
}

class _VenueNotFound implements Exception {
  const _VenueNotFound();
}

String _venueTypeLabel(VenueType type) => switch (type) {
  VenueType.bar => 'Bar',
  VenueType.club => 'Club',
  VenueType.hall => 'Hall',
  VenueType.house => 'House',
  VenueType.outdoor => 'Outdoor',
  VenueType.other => 'Other',
};
