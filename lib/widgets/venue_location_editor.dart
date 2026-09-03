import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_map.dart';
import 'ep_sheet.dart';
import 'form_bits.dart';
import 'sheets.dart';

/// Creates (or resolves to an existing) venue from the editor's fields —
/// the shape of [AppState.createVenue].
typedef VenueLocationSubmit =
    Future<VenueCreationResult> Function({
      required String name,
      required String area,
      required String address,
      required LatLng point,
    });

/// Opens the new-venue sheet wired to the current [AppState].
void showNewVenueSheet(BuildContext context) {
  final app = context.read<AppState>();
  showEpSheet(
    context,
    (_) => EpFormSheet(
      title: 'New venue',
      child: _NewVenueSheetBody(onSubmit: app.createVenue, onSaved: app.say),
    ),
  );
}

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

class _NewVenueSheetBody extends StatefulWidget {
  const _NewVenueSheetBody({required this.onSubmit, required this.onSaved});

  final VenueLocationSubmit onSubmit;
  final ValueChanged<String> onSaved;

  @override
  State<_NewVenueSheetBody> createState() => _NewVenueSheetBodyState();
}

class _NewVenueSheetBodyState extends State<_NewVenueSheetBody> {
  VenueLocationDraft _draft = const VenueLocationDraft();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final draft = _draft;
    if (!draft.isComplete) {
      setState(
        () => _error = 'Name, street address, area, and map pin are required.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(
        name: draft.name,
        area: draft.area,
        address: draft.address,
        point: draft.pin!,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved(
        result.created
            ? 'Venue created and selected.'
            : 'Existing venue selected.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Venue could not be created. Check the details and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VenueLocationEditor(
          initial: _draft,
          onChanged: (draft) => setState(() => _draft = draft),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Text(error, style: epText(size: 11, color: context.epColors.warning)),
        ],
        const SizedBox(height: 12),
        EpButton(
          _saving ? 'CREATING…' : 'CREATE & SELECT VENUE',
          kind: _saving ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}
