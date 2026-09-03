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
      child: VenueLocationEditor(onSubmit: app.createVenue, onSaved: app.say),
    ),
  );
}

/// Name, street address, area and a tap-to-place map pin for a new venue.
/// Validates locally, then hands the fields to [onSubmit]; on success it pops
/// the enclosing sheet and reports the outcome through [onSaved].
class VenueLocationEditor extends StatefulWidget {
  const VenueLocationEditor({
    super.key,
    required this.onSubmit,
    required this.onSaved,
  });

  final VenueLocationSubmit onSubmit;

  /// Receives the confirmation message once the venue is created or reused.
  final ValueChanged<String> onSaved;

  @override
  State<VenueLocationEditor> createState() => _VenueLocationEditorState();
}

class _VenueLocationEditorState extends State<VenueLocationEditor> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _area = TextEditingController();
  LatLng? _pin;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pin;
    if (_name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        _area.text.trim().isEmpty ||
        pin == null) {
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
        name: _name.text,
        area: _area.text,
        address: _address.text,
        point: pin,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved(
        result.created
            ? 'Venue created and selected.'
            : 'Existing venue selected.',
      );
    } catch (error) {
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
    const center = LatLng(37.7749, -122.4194);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('new-venue-name'),
          controller: _name,
          maxLength: 120,
          decoration: sheetInput(context, 'Venue name'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('new-venue-address'),
          controller: _address,
          maxLength: 240,
          decoration: sheetInput(context, 'Street address'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('new-venue-area'),
          controller: _area,
          maxLength: 80,
          decoration: sheetInput(context, 'Neighborhood or city'),
        ),
        const SizedBox(height: 10),
        Text(
          _pin == null
              ? 'TAP THE MAP TO PLACE THE REQUIRED PIN'
              : 'MAP PIN SET ✓',
          style: epText(
            size: 11,
            weight: FontWeight.w900,
            color: _pin == null
                ? context.epColors.warning
                : context.epColors.accent,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          key: const Key('new-venue-map'),
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: EpMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 11.5,
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
