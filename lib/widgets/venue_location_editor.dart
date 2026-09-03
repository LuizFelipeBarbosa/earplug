import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'ep_map.dart';
import 'form_bits.dart';

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

  bool get isComplete =>
      name.trim().isNotEmpty &&
      address.trim().isNotEmpty &&
      area.trim().isNotEmpty &&
      pin != null;

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

/// Controlled name, address, area, and tap-to-place map-pin fields.
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
  });

  final VenueLocationDraft initial;
  final ValueChanged<VenueLocationDraft> onChanged;
  final bool showNameField;
  final String keyPrefix;
  final LatLng initialCenter;
  final double initialZoom;
  final String? helperText;

  @override
  State<VenueLocationEditor> createState() => _VenueLocationEditorState();
}

class _VenueLocationEditorState extends State<VenueLocationEditor> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _area;
  late VenueLocationDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _name = TextEditingController(text: _draft.name);
    _address = TextEditingController(text: _draft.address);
    _area = TextEditingController(text: _draft.area);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _area.dispose();
    super.dispose();
  }

  void _emit(VenueLocationDraft draft) {
    setState(() => _draft = draft);
    widget.onChanged(draft);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showNameField) ...[
          TextField(
            key: Key('${widget.keyPrefix}-name'),
            controller: _name,
            maxLength: 120,
            decoration: sheetInput(context, 'Venue name'),
            onChanged: (name) => _emit(_draft.copyWith(name: name)),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          key: Key('${widget.keyPrefix}-address'),
          controller: _address,
          maxLength: 240,
          decoration: sheetInput(context, 'Street address'),
          onChanged: (address) => _emit(_draft.copyWith(address: address)),
        ),
        const SizedBox(height: 8),
        TextField(
          key: Key('${widget.keyPrefix}-area'),
          controller: _area,
          maxLength: 80,
          decoration: sheetInput(context, 'Neighborhood or city'),
          onChanged: (area) => _emit(_draft.copyWith(area: area)),
        ),
        const SizedBox(height: 10),
        Text(
          widget.helperText ??
              (_draft.pin == null
                  ? 'TAP THE MAP TO PLACE THE REQUIRED PIN'
                  : 'MAP PIN SET ✓'),
          style: epText(
            size: 11,
            weight: FontWeight.w900,
            color: widget.helperText != null
                ? context.epColors.contentDisabled
                : _draft.pin == null
                ? context.epColors.warning
                : context.epColors.accent,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          key: Key('${widget.keyPrefix}-map'),
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: EpMap(
              options: MapOptions(
                initialCenter: widget.initialCenter,
                initialZoom: widget.initialZoom,
                backgroundColor: context.epColors.background,
                onTap: (_, point) => _emit(_draft.copyWith(pin: point)),
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
  }
}
