import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/geocoding_service.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_map.dart';
import 'ep_sheet.dart';
import 'sheets.dart';

class VenueLocationDraft {
  const VenueLocationDraft({
    this.name = '',
    this.address = '',
    this.area = '',
    this.pin,
  });

  final String name;
  final String address;
  final String area;
  final LatLng? pin;

  bool get isComplete => address.trim().isNotEmpty && pin != null;
  String get areaLabel => area.trim().isEmpty ? 'Bay Area' : area.trim();
  bool get isNamed => name.trim().isNotEmpty;

  VenueLocationDraft copyWith({
    String? name,
    String? address,
    String? area,
    LatLng? pin,
  }) {
    return VenueLocationDraft(
      name: name ?? this.name,
      address: address ?? this.address,
      area: area ?? this.area,
      pin: pin ?? this.pin,
    );
  }
}

/// Address autocomplete and tap-to-place map-pin fields for a venue.
class VenueLocationEditor extends StatefulWidget {
  const VenueLocationEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.showNameField = true,
    this.keyPrefix = 'new-venue',
    this.initialCenter = const LatLng(37.7749, -122.4194),
    this.initialZoom = 11.5,
    this.helperText,
    this.enabled = true,
    this.compactMap = false,
    this.geocoding,
  });

  final VenueLocationDraft initial;
  final ValueChanged<VenueLocationDraft> onChanged;
  final bool showNameField;
  final String keyPrefix;
  final LatLng initialCenter;
  final double initialZoom;
  final String? helperText;
  final bool enabled;

  /// Shows a neighborhood thumbnail and edits the exact pin in a sheet.
  final bool compactMap;
  final GeocodingService? geocoding;

  @override
  State<VenueLocationEditor> createState() => _VenueLocationEditorState();
}

class _VenueLocationEditorState extends State<VenueLocationEditor> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late VenueLocationDraft _draft;
  late final GeocodingService _geocoding;
  final MapController _controller = MapController();

  List<AddressSuggestion> _suggestions = [];
  bool _loading = false;
  bool _searchUnavailable = false;
  String? _transientError;
  Timer? _debounce;
  int _requestId = 0;
  bool _suppressNextChange = false;
  bool _mapReady = false;
  ({LatLng point, double zoom})? _pendingMove;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _name = TextEditingController(text: _draft.name);
    _address = TextEditingController(text: _draft.address);
    _geocoding = widget.geocoding ?? context.read<GeocodingService>();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _requestId++;
    _controller.dispose();
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _emit(VenueLocationDraft draft) {
    setState(() => _draft = draft);
    widget.onChanged(draft);
  }

  void _onAddressChanged(String text) {
    if (_suppressNextChange) {
      _suppressNextChange = false;
      return;
    }

    _emit(_draft.copyWith(address: text));
    _debounce?.cancel();

    if (text.trim().length < 3) {
      _requestId++;
      setState(() {
        _suggestions = [];
        _loading = false;
        _transientError = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  Future<void> _search(String text) async {
    if (_searchUnavailable) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _transientError = null;
    });

    try {
      final results = await _geocoding.autocomplete(
        text,
        focus: widget.initialCenter,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _suggestions = results;
        _loading = false;
        _transientError = null;
      });
    } on GeocodingUnauthorized {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _searchUnavailable = true;
        _suggestions = [];
        _loading = false;
      });
    } on GeocodingFailure {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _transientError = "Couldn't search. Try again.";
        _suggestions = [];
        _loading = false;
      });
    }
  }

  void _clearAddress() {
    if (!widget.enabled) return;
    _suppressNextChange = true;
    _address.clear();
    _suppressNextChange = false;
    _debounce?.cancel();
    _requestId++;
    _emit(_draft.copyWith(address: ''));
    setState(() {
      _suggestions = [];
      _loading = false;
      _transientError = null;
    });
  }

  void _pickSuggestion(AddressSuggestion suggestion) {
    if (!widget.enabled) return;
    _suppressNextChange = true;
    _address.text = suggestion.address;
    _suppressNextChange = false;
    _debounce?.cancel();
    _requestId++;
    _emit(
      _draft.copyWith(
        address: suggestion.address,
        area: suggestion.area,
        pin: suggestion.point,
      ),
    );
    setState(() {
      _suggestions = [];
      _loading = false;
      _transientError = null;
    });
    _moveTo(suggestion.point, 16);
  }

  void _moveTo(LatLng point, double zoom) {
    if (widget.compactMap) return;
    if (!_mapReady) {
      _pendingMove = (point: point, zoom: zoom);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      _controller.move(point, zoom);
    });
  }

  void _onMapReady() {
    _mapReady = true;
    if (_pendingMove case final move?) {
      _controller.move(move.point, move.zoom);
      _pendingMove = null;
    }
  }

  void _setPin(LatLng point) {
    if (!widget.enabled) return;
    _emit(_draft.copyWith(pin: point));
    setState(() => _suggestions = []);
  }

  Future<void> _editPin() async {
    if (!widget.enabled) return;
    FocusScope.of(context).unfocus();
    await showEpSheet(
      context,
      (sheetContext) => _VenuePinSheet(
        keyPrefix: widget.keyPrefix,
        initialPin: _draft.pin,
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        onDone: (pin) {
          if (mounted && widget.enabled) _setPin(pin);
          Navigator.pop(sheetContext);
        },
      ),
    );
  }

  Widget _neighborhoodPreview(BuildContext context) {
    final pin = _draft.pin;
    // Keep the preview at neighborhood scale, without an exact-location marker.
    final center = pin == null
        ? widget.initialCenter
        : LatLng(
            (pin.latitude * 100).round() / 100,
            (pin.longitude * 100).round() / 100,
          );
    return Material(
      color: context.epColors.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('${widget.keyPrefix}-preview'),
        onTap: widget.enabled ? _editPin : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 104,
                  height: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.noScaling),
                      child: EpMap(
                        key: ValueKey(center),
                        showAttribution: false,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: widget.initialZoom,
                          backgroundColor: context.epColors.background,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FANS WILL SEE',
                      style: Theme.of(context).textTheme.epLabel.copyWith(
                        color: context.epColors.contentSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _draft.areaLabel,
                      key: Key('${widget.keyPrefix}-area-caption'),
                      style: Theme.of(
                        context,
                      ).textTheme.epBody.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pin == null ? 'Place map pin' : 'Adjust map pin',
                      style: Theme.of(context).textTheme.epCaption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: context.epColors.contentSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestionList(BuildContext context) {
    return Container(
      key: Key('${widget.keyPrefix}-suggestions'),
      decoration: BoxDecoration(
        border: Border.all(color: context.epColors.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < _suggestions.length; index++)
            InkWell(
              key: Key('${widget.keyPrefix}-suggestion-$index'),
              onTap: widget.enabled
                  ? () => _pickSuggestion(_suggestions[index])
                  : null,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_suggestions[index].label),
                          const SizedBox(height: 3),
                          Text(
                            _suggestions[index].area,
                            style: Theme.of(context).textTheme.epCaption,
                          ),
                        ],
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

  @override
  Widget build(BuildContext context) {
    final initialPin = widget.initial.pin;
    final pinHint = _draft.pin == null
        ? 'Pick a suggestion or tap the map to place the pin'
        : 'Tap the map to adjust the pin';

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showNameField) ...[
          TextField(
            key: Key('${widget.keyPrefix}-name'),
            controller: _name,
            enabled: widget.enabled,
            maxLength: 120,
            decoration: labeledInputDecoration(
              context,
              'VENUE NAME · REQUIRED',
              "The room's name",
            ),
            onChanged: (name) => _emit(_draft.copyWith(name: name)),
          ),
          const SizedBox(height: 14),
        ],
        TextField(
          key: Key('${widget.keyPrefix}-address'),
          controller: _address,
          enabled: widget.enabled,
          maxLength: 240,
          decoration: labeledInputDecoration(
            context,
            'STREET ADDRESS · REQUIRED',
            'Start typing the address',
          ).copyWith(suffixIcon: _addressSuffix()),
          onChanged: _onAddressChanged,
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 14),
          _suggestionList(context),
        ],
        const SizedBox(height: 14),
        if (widget.helperText case final helper?) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 15,
                color: context.epColors.contentDisabled,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  helper,
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (_searchUnavailable || _transientError != null) ...[
          Text(
            _searchUnavailable
                ? widget.compactMap
                      ? 'Address search is unavailable. Open the neighborhood card to place the pin.'
                      : 'Address search is unavailable. Tap the map to place the pin.'
                : _transientError!,
            key: Key(
              '${widget.keyPrefix}-${_searchUnavailable ? 'search-unavailable' : 'search-error'}',
            ),
            style: Theme.of(
              context,
            ).textTheme.epCaption.copyWith(color: context.epColors.warning),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.compactMap)
          _neighborhoodPreview(context)
        else ...[
          Text(
            'Fans will see: ${_draft.areaLabel}',
            key: Key('${widget.keyPrefix}-area-caption'),
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 14),
          Text(
            pinHint,
            style: Theme.of(context).textTheme.epCaption.copyWith(
              fontWeight: FontWeight.w700,
              color: _draft.pin == null
                  ? context.epColors.warning
                  : context.epColors.accent,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            key: Key('${widget.keyPrefix}-map'),
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: EpMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: initialPin ?? widget.initialCenter,
                  initialZoom: initialPin == null ? widget.initialZoom : 15,
                  backgroundColor: context.epColors.background,
                  onTap: (_, point) => _setPin(point),
                  onMapReady: _onMapReady,
                ),
                layers: [
                  if (_draft.pin case final pin?)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: pin,
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.location_pin,
                            color: context.epColors.accent,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    if (widget.enabled) return column;
    return Opacity(opacity: 0.62, child: IgnorePointer(child: column));
  }

  Widget? _addressSuffix() {
    if (_loading) {
      return const Center(
        child: SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_address.text.isEmpty) return null;
    return IconButton(
      tooltip: 'Clear address',
      onPressed: widget.enabled ? _clearAddress : null,
      icon: const Icon(Icons.close),
    );
  }
}

class _VenuePinSheet extends StatefulWidget {
  const _VenuePinSheet({
    required this.keyPrefix,
    required this.initialPin,
    required this.initialCenter,
    required this.initialZoom,
    required this.onDone,
  });

  final String keyPrefix;
  final LatLng? initialPin;
  final LatLng initialCenter;
  final double initialZoom;
  final ValueChanged<LatLng> onDone;

  @override
  State<_VenuePinSheet> createState() => _VenuePinSheetState();
}

class _VenuePinSheetState extends State<_VenuePinSheet> {
  late LatLng? _pin = widget.initialPin;

  @override
  Widget build(BuildContext context) {
    return EpSheetShell(
      heightFactor: .8,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      header: Row(
        children: [
          Expanded(
            child: Text(
              'VENUE MAP PIN',
              style: Theme.of(context).textTheme.epSection,
            ),
          ),
          CircleIconButton(
            icon: Icons.close,
            key: Key('${widget.keyPrefix}-pin-cancel'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
      children: [
        Text(
          'Tap the map to place or adjust the pin. The exact address stays private.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: EpMap(
              key: Key('${widget.keyPrefix}-pin-map'),
              options: MapOptions(
                initialCenter: widget.initialPin ?? widget.initialCenter,
                initialZoom: widget.initialPin == null
                    ? widget.initialZoom
                    : 15,
                backgroundColor: context.epColors.background,
                onTap: (_, point) => setState(() => _pin = point),
              ),
              layers: [
                if (_pin case final pin?)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pin,
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.location_pin,
                          color: context.epColors.accent,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: Key('${widget.keyPrefix}-pin-done'),
          onPressed: _pin == null ? null : () => widget.onDone(_pin!),
          child: const Text('DONE'),
        ),
      ],
    );
  }
}
