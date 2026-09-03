import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/approx_area_map.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import '../widgets/venue_location_editor.dart';

class OrgVenuesScreen extends StatefulWidget {
  const OrgVenuesScreen({super.key});

  @override
  State<OrgVenuesScreen> createState() => _OrgVenuesScreenState();
}

class _OrgVenuesScreenState extends State<OrgVenuesScreen> {
  OrganizationDashboard? _dashboard;
  Object? _error;
  bool _loading = true;
  String? _loadedOrganizationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final organizationId = context.read<AppState>().organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _refresh();
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await app.repository.organizationDashboard(
        organizationId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _dashboard = dashboard;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _openVenue(Venue venue) {
    final app = context.read<AppState>();
    showEpSheet(
      context,
      (_) => _VenueEditorSheet(
        venue: venue,
        canManage: app.canManageOrganization(app.organizationId),
        isOwner:
            app.organizerRoleFor(app.organizationId) == OrganizationRole.owner,
        onSaved: _refresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venues = _dashboard?.venues ?? const <Venue>[];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Text('VENUES', style: epDisplay(size: 22)),
        const SizedBox(height: 4),
        Text(
          app.canManageOrganization(app.organizationId)
              ? 'Manage public venue profiles and private operational details.'
              : 'View public venue profiles and private operational details.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 10),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _LoadError(onRetry: _refresh)
        else if (venues.isEmpty)
          const EpCard(
            child: Text('No venues are connected to this organization.'),
          )
        else
          for (final venue in venues) ...[
            EpCard(
              key: ValueKey('org-venue-${venue.id}'),
              onTap: () => _openVenue(venue),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(venue.name, style: epDisplay(size: 17)),
                            const SizedBox(height: 4),
                            Text(
                              venue.approx.label,
                              style: Theme.of(context).textTheme.epCaption,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(
                        label: venue.verified ? 'VERIFIED' : 'SUSPENDED',
                        tone: venue.verified
                            ? EpStatusPillTone.success
                            : EpStatusPillTone.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ApproxAreaMap(
                    centroid: venue.approx.centroid,
                    label: venue.approx.label,
                    height: 130,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _VenueEditorSheet extends StatefulWidget {
  const _VenueEditorSheet({
    required this.venue,
    required this.canManage,
    required this.isOwner,
    required this.onSaved,
  });

  final Venue venue;
  final bool canManage;
  final bool isOwner;
  final Future<void> Function() onSaved;

  @override
  State<_VenueEditorSheet> createState() => _VenueEditorSheetState();
}

class _VenueEditorSheetState extends State<_VenueEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _publicCapacity;
  late final TextEditingController _neighborhood;
  late final TextEditingController _city;
  late final TextEditingController _loadInNotes;
  late final TextEditingController _privateCapacity;
  VenueType _venueType = VenueType.other;
  VenueLocationDraft? _location;
  late AddressDisclosure _disclosure;
  bool _privateLoading = true;
  bool _savingPublic = false;
  bool _savingPrivate = false;
  bool _savingDisclosure = false;
  Object? _privateError;

  @override
  void initState() {
    super.initState();
    final venue = widget.venue;
    _name = TextEditingController(text: venue.name);
    _description = TextEditingController(text: venue.description ?? '');
    _publicCapacity = TextEditingController(
      text: venue.capacityPublic?.toString() ?? '',
    );
    _venueType = venue.venueType ?? VenueType.other;
    _neighborhood = TextEditingController(text: venue.neighborhood ?? '');
    _city = TextEditingController(text: venue.city ?? '');
    _loadInNotes = TextEditingController();
    _privateCapacity = TextEditingController();
    _disclosure = venue.disclosure;
    _loadPrivateDetails();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _publicCapacity.dispose();
    _neighborhood.dispose();
    _city.dispose();
    _loadInNotes.dispose();
    _privateCapacity.dispose();
    super.dispose();
  }

  Future<void> _loadPrivateDetails() async {
    setState(() {
      _privateLoading = true;
      _privateError = null;
    });
    try {
      final details = await context
          .read<AppState>()
          .repository
          .venuePrivateDetails(widget.venue.id);
      if (!mounted) return;
      _loadInNotes.text = details?.loadInNotes ?? '';
      _privateCapacity.text = details?.capacity?.toString() ?? '';
      setState(() {
        _location = VenueLocationDraft(
          address: details?.addr ?? '',
          area: widget.venue.neighborhood ?? widget.venue.city ?? '',
          pin: details?.point,
        );
        _privateLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _privateError = error;
        _privateLoading = false;
      });
    }
  }

  Future<void> _savePublic() async {
    if (_savingPublic || !widget.canManage) return;
    setState(() => _savingPublic = true);
    final app = context.read<AppState>();
    try {
      await app.repository.updateVenueProfile(
        venueId: widget.venue.id,
        name: _name.text.trim(),
        description: _description.text.trim(),
        venueType: _venueType,
        capacityPublic: int.tryParse(_publicCapacity.text.trim()),
        neighborhood: _neighborhood.text.trim(),
        city: _city.text.trim(),
      );
      await widget.onSaved();
      if (mounted) app.say('Venue profile saved.');
    } catch (_) {
      if (mounted) app.say('Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => _savingPublic = false);
    }
  }

  Future<void> _savePrivate() async {
    final location = _location;
    if (_savingPrivate || !widget.canManage || location?.pin == null) return;
    setState(() => _savingPrivate = true);
    final app = context.read<AppState>();
    try {
      await app.repository.updateVenuePrivateDetails(
        venueId: widget.venue.id,
        addr: location!.address.trim(),
        point: location.pin!,
        loadInNotes: _loadInNotes.text.trim(),
        capacity: int.tryParse(_privateCapacity.text.trim()),
      );
      await widget.onSaved();
      if (mounted) app.say('Private venue details saved.');
    } catch (_) {
      if (mounted) app.say('Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => _savingPrivate = false);
    }
  }

  Future<void> _setDisclosure(bool disclosePublicly) async {
    if (_savingDisclosure || !widget.isOwner) return;
    setState(() => _savingDisclosure = true);
    final app = context.read<AppState>();
    final disclosure = disclosePublicly
        ? AddressDisclosure.public
        : AddressDisclosure.onTicket;
    try {
      await app.repository.setVenueAddressDisclosure(
        venueId: widget.venue.id,
        disclosure: disclosure,
      );
      if (!mounted) return;
      setState(() => _disclosure = disclosure);
      await widget.onSaved();
      if (mounted) app.say('Address disclosure saved.');
    } catch (_) {
      if (mounted) app.say('Could not save. Please retry.');
    } finally {
      if (mounted) setState(() => _savingDisclosure = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpSheetShell(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      maxHeightFactor: .92,
      scrollable: true,
      mainAxisSize: MainAxisSize.min,
      header: Row(
        children: [
          Expanded(
            child: Text(
              widget.venue.name.toUpperCase(),
              style: epDisplay(size: 16),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      children: [
        FormSection(
          title: 'Public profile',
          description:
              'These details appear anywhere EarPlug shows this venue.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('org-venue-public-name'),
                controller: _name,
                enabled: widget.canManage,
                decoration: labeledInputDecoration(
                  context,
                  'Venue name',
                  'Venue name',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('org-venue-public-description'),
                controller: _description,
                enabled: widget.canManage,
                minLines: 3,
                maxLines: 5,
                decoration: labeledInputDecoration(
                  context,
                  'Description',
                  'Tell artists and fans about the venue',
                ),
              ),
              const SizedBox(height: 12),
              _FieldLabel('VENUE TYPE'),
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
                      onTap: widget.canManage
                          ? () => setState(() => _venueType = type)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('org-venue-public-capacity'),
                controller: _publicCapacity,
                enabled: widget.canManage,
                keyboardType: TextInputType.number,
                decoration: labeledInputDecoration(
                  context,
                  'Public capacity',
                  'Optional',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('org-venue-public-neighborhood'),
                controller: _neighborhood,
                enabled: widget.canManage,
                decoration: labeledInputDecoration(
                  context,
                  'Neighborhood',
                  'Neighborhood',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('org-venue-public-city'),
                controller: _city,
                enabled: widget.canManage,
                decoration: labeledInputDecoration(context, 'City', 'City'),
              ),
              if (widget.canManage) ...[
                const SizedBox(height: 12),
                EpButton(
                  _savingPublic ? 'SAVING…' : 'SAVE PUBLIC PROFILE',
                  key: const Key('org-venue-save-public'),
                  kind: _savingPublic
                      ? EpButtonKind.disabled
                      : EpButtonKind.filled,
                  onTap: _savingPublic ? null : _savePublic,
                ),
              ],
            ],
          ),
        ),
        FormSection(
          title: 'Private location',
          description:
              'Exact access details stay private unless address disclosure is enabled.',
          child: _privateSection(context),
        ),
        FormSection(
          title: 'Address disclosure',
          description: 'Control when the exact address becomes visible.',
          child: SwitchRow(
            key: const Key('org-venue-disclosure'),
            label: 'Show exact address publicly',
            value: _disclosure == AddressDisclosure.public,
            onChanged: widget.isOwner && !_savingDisclosure
                ? _setDisclosure
                : null,
            caption:
                'Otherwise the exact address is shared privately with booked artists and ticket holders, not shown publicly.',
          ),
        ),
      ],
    );
  }

  Widget _privateSection(BuildContext context) {
    if (_privateLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_privateError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Could not load private venue details.'),
          const SizedBox(height: 8),
          EpButton(
            'RETRY',
            kind: EpButtonKind.outline,
            onTap: _loadPrivateDetails,
          ),
        ],
      );
    }
    final location = _location!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          ignoring: !widget.canManage,
          child: Opacity(
            opacity: widget.canManage ? 1 : .62,
            child: VenueLocationEditor(
              initial: location,
              onChanged: (draft) => setState(() => _location = draft),
              showNameField: false,
              keyPrefix: 'org-venue-private',
              initialCenter: location.pin ?? widget.venue.approx.centroid,
              initialZoom: location.pin == null ? 11.5 : 15,
              helperText: widget.canManage
                  ? null
                  : 'Private location is read-only for your role.',
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('org-venue-private-load-in'),
          controller: _loadInNotes,
          enabled: widget.canManage,
          minLines: 2,
          maxLines: 4,
          decoration: labeledInputDecoration(
            context,
            'Load-in notes',
            'Entrances, stairs, parking, or access notes',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('org-venue-private-capacity'),
          controller: _privateCapacity,
          enabled: widget.canManage,
          keyboardType: TextInputType.number,
          decoration: labeledInputDecoration(
            context,
            'Private capacity',
            'Optional',
          ),
        ),
        if (widget.canManage) ...[
          const SizedBox(height: 12),
          EpButton(
            _savingPrivate ? 'SAVING…' : 'SAVE PRIVATE LOCATION',
            key: const Key('org-venue-save-private'),
            kind: _savingPrivate || location.pin == null
                ? EpButtonKind.disabled
                : EpButtonKind.filled,
            onTap: _savingPrivate || location.pin == null ? null : _savePrivate,
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.epLabel.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: .8,
        color: context.epColors.contentSecondary,
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 56),
        const Text('Could not load venues.'),
        const SizedBox(height: 12),
        EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
      ],
    );
  }
}

String _venueTypeLabel(VenueType type) => switch (type) {
  VenueType.bar => 'Bar',
  VenueType.club => 'Club',
  VenueType.hall => 'Hall',
  VenueType.house => 'House',
  VenueType.outdoor => 'Outdoor',
  VenueType.other => 'Other',
};
