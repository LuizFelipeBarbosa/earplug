import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/venue_location_editor.dart';

class PrivateLocationsScreen extends StatefulWidget {
  const PrivateLocationsScreen({super.key});

  @override
  State<PrivateLocationsScreen> createState() => _PrivateLocationsScreenState();
}

class _PrivateLocationsScreenState extends State<PrivateLocationsScreen> {
  List<PrivateLocation> _locations = const [];
  String? _loadedOrganizationId;
  bool _loading = true;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final organizationId = context.read<AppState>().organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locations = await app.repository.privateLocationsFor(
        organizationId,
      );
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _locations = locations;
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: context.epColors.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          headerTopPad(context),
          16,
          tabBarClearance,
        ),
        children: [
          Row(
            children: [
              CircleIconButton(onTap: app.back),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'LOCATIONS',
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          EpButton(
            'NEW LOCATION',
            key: const Key('private-locations-new'),
            onTap: app.canManageOrganization(app.organizationId)
                ? () => app.go(Screen.privateLocationEdit, 'new')
                : null,
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _LoadError(message: 'Could not load locations.', onRetry: _load)
          else if (_locations.isEmpty)
            const Text(
              'No locations yet. Add the place where your event happens; artists see only the area until the deposit is paid.',
            )
          else
            for (final location in _locations) ...[
              EpCard(
                key: ValueKey('private-location-${location.id}'),
                onTap: () => app.go(Screen.privateLocationEdit, location.id),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            location.label,
                            style: Theme.of(context).textTheme.epSectionHeading,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            location.area,
                            style: Theme.of(context).textTheme.epCaption,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class PrivateLocationEditScreen extends StatefulWidget {
  const PrivateLocationEditScreen({super.key, required this.locationId});

  final String locationId;

  @override
  State<PrivateLocationEditScreen> createState() =>
      _PrivateLocationEditScreenState();
}

class _PrivateLocationEditScreenState extends State<PrivateLocationEditScreen> {
  final _scroll = ScrollController();
  final _label = TextEditingController();
  final _city = TextEditingController();
  final _notes = TextEditingController();
  VenueLocationDraft _location = const VenueLocationDraft();
  String? _loadedKey;
  String? _loadError;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _cityPrefilled = false;
  int _editorRevision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant PrivateLocationEditScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureLoaded();
  }

  void _ensureLoaded() {
    final organizationId = context.read<AppState>().organizationId;
    final key = '$organizationId:${widget.locationId}';
    if (_loadedKey == key) return;
    _loadedKey = key;
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final key = _loadedKey;
    final organizationId = app.organizationId;
    final locationId = widget.locationId;
    setState(() {
      _loading = true;
      _loadError = null;
      _error = null;
    });
    try {
      PrivateLocation? location;
      if (locationId != 'new') {
        final locations = await app.repository.privateLocationsFor(
          organizationId,
        );
        location = locations.where((item) => item.id == locationId).firstOrNull;
        if (location == null) {
          throw StateError(
            'This location is not connected to this organization.',
          );
        }
      }
      if (!mounted ||
          key != _loadedKey ||
          app.organizationId != organizationId) {
        return;
      }
      setState(() {
        _label.text = location?.label ?? '';
        _city.text = location?.city ?? '';
        _notes.text = location?.notes ?? '';
        _location = VenueLocationDraft(
          address: location?.addr ?? '',
          area: location?.area ?? '',
          pin: location == null ? null : LatLng(location.lat, location.lng),
        );
        _cityPrefilled = location != null;
        _editorRevision++;
        _loading = false;
      });
    } catch (error) {
      if (!mounted ||
          key != _loadedKey ||
          app.organizationId != organizationId) {
        return;
      }
      setState(() {
        _loadError = serverErrorMessage(error) ?? error.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _label.dispose();
    _city.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _draftChanged([String? _]) {
    if (_error != null) setState(() => _error = null);
  }

  void _locationChanged(VenueLocationDraft draft) {
    setState(() {
      _location = draft;
      if (!_cityPrefilled && draft.pin != null) {
        _cityPrefilled = true;
        final city = draft.city?.trim();
        if (_city.text.trim().isEmpty && city != null && city.isNotEmpty) {
          _city.text = city;
        }
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    if (_busy || !app.canManageOrganization(app.organizationId)) return;
    final needs = [
      if (_label.text.trim().isEmpty) 'label',
      if (_location.address.trim().isEmpty) 'address',
      if (_location.pin == null) 'map pin',
      if (_city.text.trim().isEmpty) 'city',
    ];
    if (needs.isNotEmpty) {
      setState(() => _error = 'Needs: ${needs.join(', ')}');
      revealFormFeedback(this, _scroll);
      return;
    }
    final pin = _location.pin!;
    final organizationId = app.organizationId;
    final key = _loadedKey;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.locationId == 'new') {
        await app.repository.createPrivateLocation(
          organizationId: organizationId,
          label: _label.text.trim(),
          addr: _location.address.trim(),
          city: _city.text.trim(),
          area: _location.areaLabel,
          lat: pin.latitude,
          lng: pin.longitude,
          notes: _notes.text.trim(),
        );
      } else {
        await app.repository.updatePrivateLocation(
          widget.locationId,
          label: _label.text.trim(),
          addr: _location.address.trim(),
          city: _city.text.trim(),
          area: _location.areaLabel,
          lat: pin.latitude,
          lng: pin.longitude,
          notes: _notes.text.trim(),
        );
      }
      if (mounted &&
          key == _loadedKey &&
          app.organizationId == organizationId) {
        app.back();
      }
    } catch (error) {
      if (!mounted ||
          key != _loadedKey ||
          app.organizationId != organizationId) {
        return;
      }
      setState(() => _error = serverErrorMessage(error) ?? error.toString());
      revealFormFeedback(this, _scroll);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final app = context.read<AppState>();
    if (_busy || !app.canManageOrganization(app.organizationId)) return;
    final organizationId = app.organizationId;
    final key = _loadedKey;
    final locationId = widget.locationId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('REMOVE LOCATION?'),
        content: Text('Remove ${_label.text.trim()} from your locations?'),
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
    if (!mounted ||
        confirmed != true ||
        key != _loadedKey ||
        app.organizationId != organizationId) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.repository.removePrivateLocation(locationId);
      if (mounted &&
          key == _loadedKey &&
          app.organizationId == organizationId) {
        app.back();
      }
    } catch (error) {
      if (!mounted ||
          key != _loadedKey ||
          app.organizationId != organizationId) {
        return;
      }
      setState(() => _error = serverErrorMessage(error) ?? error.toString());
      revealFormFeedback(this, _scroll);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final enabled = app.canManageOrganization(app.organizationId) && !_busy;
    return Scaffold(
      backgroundColor: context.epColors.background,
      body: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          headerTopPad(context),
          16,
          tabBarClearance,
        ),
        children: [
          Row(
            children: [
              CircleIconButton(onTap: app.back),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.locationId == 'new' ? 'NEW LOCATION' : 'EDIT LOCATION',
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadError != null)
            _LoadError(message: _loadError!, onRetry: _load)
          else ...[
            FormSection(
              title: 'LOCATION',
              description:
                  'Artists see the area only. The exact address is shared after the deposit.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EpLabeledField(
                    fieldKey: const Key('private-location-label'),
                    label: 'LABEL',
                    hint: 'Backyard',
                    controller: _label,
                    required: true,
                    enabled: enabled,
                    onChanged: _draftChanged,
                  ),
                  const SizedBox(height: EpLayout.fieldGap),
                  VenueLocationEditor(
                    key: ValueKey('private-location-editor-$_editorRevision'),
                    keyPrefix: 'private-location',
                    initial: _location,
                    onChanged: _locationChanged,
                    showNameField: false,
                    audienceLabel: 'Artists',
                    enabled: enabled,
                    helperText:
                        'The exact address is shared after the deposit.',
                    initialCenter:
                        _location.pin ?? const LatLng(37.7749, -122.4194),
                    initialZoom: _location.pin == null ? 11.5 : 15,
                  ),
                  const SizedBox(height: EpLayout.fieldGap),
                  EpLabeledField(
                    fieldKey: const Key('private-location-city'),
                    label: 'CITY',
                    hint: 'City',
                    controller: _city,
                    required: true,
                    enabled: enabled,
                    onChanged: _draftChanged,
                  ),
                  const SizedBox(height: EpLayout.fieldGap),
                  EpLabeledField(
                    fieldKey: const Key('private-location-notes'),
                    label: 'NOTES',
                    hint: 'Load-in, parking, gate code…',
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    enabled: enabled,
                    onChanged: _draftChanged,
                  ),
                ],
              ),
            ),
            InlineFormFeedback(
              error: _error,
              errorKey: const Key('private-location-feedback'),
            ),
            const SizedBox(height: 16),
            EpButton(
              _busy ? 'SAVING…' : 'SAVE',
              key: const Key('private-location-save'),
              onTap: enabled ? _save : null,
            ),
            if (widget.locationId != 'new') ...[
              const SizedBox(height: 12),
              EpButton(
                'REMOVE',
                key: const Key('private-location-remove'),
                kind: EpButtonKind.outline,
                onTap: enabled ? _remove : null,
              ),
            ],
          ],
        ],
      ),
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
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
        ],
      ),
    );
  }
}
