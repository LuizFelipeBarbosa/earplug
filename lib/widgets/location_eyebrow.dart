import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../services/location_service.dart';
import '../theme.dart';
import 'ep_text.dart';

/// "FRI 13 SEP · USE MY LOCATION" — the date, then the location link that
/// requests a fix and shows the resolved neighbourhood; a dismissible note
/// sits beneath when the request failed.
class DiscoveryLocationEyebrow extends StatelessWidget {
  const DiscoveryLocationEyebrow({super.key, this.controlKey, this.failureKey});

  /// Key for the location link, so each screen's tests can target its own.
  final Key? controlKey;

  /// Key for the failure note, so each screen's tests can target its own.
  final Key? failureKey;

  @override
  Widget build(BuildContext context) {
    final today = context.read<AppState>().firstSelectableDiscoveryDate;
    final (:locationLabel, :usingCurrentLocation, :locating, :locationFailure) =
        context.select<
          AppState,
          ({
            String locationLabel,
            bool usingCurrentLocation,
            bool locating,
            LocationFailure? locationFailure,
          })
        >(
          (app) => (
            locationLabel: app.locationLabel,
            usingCurrentLocation: app.usingCurrentLocation,
            locating: app.locating,
            locationFailure: app.locationFailure,
          ),
        );
    final app = context.read<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            EpEyebrow.accent(
              '${weekdayNames[today.weekday - 1]} ${today.day} '
              '${monthNames[today.month - 1]} ·',
            ),
            _LocationLink(
              key: controlKey,
              locationLabel: locationLabel,
              usingCurrentLocation: usingCurrentLocation,
              locating: locating,
              app: app,
            ),
          ],
        ),
        if (locationFailure case final failure?) ...[
          const SizedBox(height: 6),
          _LocationFailureNote(key: failureKey, failure: failure, app: app),
        ],
      ],
    );
  }
}

class _LocationLink extends StatelessWidget {
  const _LocationLink({
    super.key,
    required this.locationLabel,
    required this.usingCurrentLocation,
    required this.locating,
    required this.app,
  });

  final String locationLabel;
  final bool usingCurrentLocation;
  final bool locating;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final text = locating
        ? 'LOCATING…'
        : usingCurrentLocation
        ? locationLabel
        : 'USE MY LOCATION';
    return Semantics(
      button: true,
      enabled: !locating,
      label: usingCurrentLocation
          ? 'Using your location. Switch off'
          : 'Use my location',
      excludeSemantics: true,
      child: InkWell(
        onTap: locating
            ? null
            : () => app.setUseCurrentLocation(!usingCurrentLocation),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            text,
            style: Theme.of(context).textTheme.epSection.copyWith(
              color: locating ? palette.muted : palette.accent,
              decoration: TextDecoration.underline,
              decorationColor: palette.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationFailureNote extends StatelessWidget {
  const _LocationFailureNote({
    super.key,
    required this.failure,
    required this.app,
  });

  final LocationFailure failure;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final (message, action) = switch (failure.reason) {
      LocationFailureReason.servicesDisabled => (
        'Location services are off. Turn them on or switch it off.',
        'Open location settings',
      ),
      LocationFailureReason.permissionDeniedForever => (
        'Location access is blocked. Allow it in settings or switch it off.',
        'Open app settings',
      ),
      LocationFailureReason.permissionDenied => (
        'Location access was denied. You can try again or switch it off.',
        null,
      ),
      LocationFailureReason.unavailable => (
        'Your location is unavailable right now. Try again or switch it off.',
        null,
      ),
    };
    final palette = context.epColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 14, color: palette.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: Theme.of(context).textTheme.epCaption),
              if (action != null && !kIsWeb)
                TextButton(
                  onPressed: app.openLocationRecoverySettings,
                  child: Text(action.toUpperCase(), semanticsLabel: action),
                ),
            ],
          ),
        ),
        EpIconPill(
          icon: Icons.close,
          semanticLabel: 'Dismiss',
          onPressed: app.dismissLocationFailure,
        ),
      ],
    );
  }
}
