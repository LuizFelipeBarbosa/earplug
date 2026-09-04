import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/geocoding_service.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_map.dart';

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
    final statusText =
        widget.helperText ??
        _transientError ??
        (_draft.pin == null
            ? 'Pick a suggestion or tap the map to place the pin'
            : 'Tap the map to adjust the pin');
    final statusColor = widget.helperText != null
        ? context.epColors.contentDisabled
        : _draft.pin == null || _transientError != null
        ? context.epColors.warning
        : context.epColors.accent;

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
        Text(
          'Fans will see: ${_draft.areaLabel}',
          key: Key('${widget.keyPrefix}-area-caption'),
          style: Theme.of(context).textTheme.epCaption,
        ),
        if (_searchUnavailable) ...[
          const SizedBox(height: 14),
          Text(
            'Address search is unavailable. Tap the map to place the pin.',
            key: Key('${widget.keyPrefix}-search-unavailable'),
            style: Theme.of(context).textTheme.epCaption,
          ),
        ],
        const SizedBox(height: 14),
        Text(
          statusText,
          style: Theme.of(context).textTheme.epCaption.copyWith(
            fontWeight: FontWeight.w700,
            color: statusColor,
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
