import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_links.dart';
import '../models.dart';
import '../theme.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

/// Builds a Google Calendar template link without context or I/O.
/// [presenterOrLineupLine] contains names resolved by the caller, never band IDs.
Uri calendarTemplateUrl({
  required Gig gig,
  Venue? venue,
  String? presenterOrLineupLine,
}) {
  String utc(DateTime time) {
    final u = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}T'
        '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  final start = gig.startsAt;
  final end = start.add(const Duration(hours: 3)); // Gig has no end time.
  final detailsLines = <String>[
    if (presenterOrLineupLine != null &&
        presenterOrLineupLine.trim().isNotEmpty)
      presenterOrLineupLine,
    if (gig.slug.trim().isNotEmpty) publicWebUrl('g/${gig.publicRef}'),
  ];
  final location = venue == null
      ? ''
      : [
          venue.name,
          venue.exactAddress,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': gig.title,
    'dates': '${utc(start)}/${utc(end)}',
    if (location.isNotEmpty) 'location': location,
    if (detailsLines.isNotEmpty) 'details': detailsLines.join('\n'),
  });
}

/// Opens the gig's Google Calendar template in a new tab or window.
Future<bool> openCalendar(
  BuildContext context,
  Gig gig,
  Venue? venue, {
  String? presenterOrLineupLine,
  ExternalUrlLauncher? launch,
}) => openExternalForUser(
  context,
  calendarTemplateUrl(
    gig: gig,
    venue: venue,
    presenterOrLineupLine: presenterOrLineupLine,
  ).toString(),
  launch: launch,
);

/// Opens directions for a venue with an exact address.
Future<bool> openDirections(
  BuildContext context,
  Venue venue, {
  ExternalUrlLauncher? launch,
}) => openExternalForUser(
  context,
  'https://www.google.com/maps/search/?api=1&query='
  '${venue.point.latitude},${venue.point.longitude}',
  launch: launch,
);

Future<bool> copyForUser(
  BuildContext context,
  String text, {
  String successMessage = 'Link copied.',
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        duration: const Duration(seconds: 2),
      ),
    );
    return true;
  } catch (error, stackTrace) {
    debugPrint('Clipboard write failed: $error\n$stackTrace');
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('COPY THIS LINK'),
        content: SelectableText(text, style: epText(size: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
    return false;
  }
}

Future<bool> openExternalForUser(
  BuildContext context,
  String value, {
  ExternalUrlLauncher? launch,
}) async {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    _showActionFailure(context, 'That link is not a valid web address.');
    return false;
  }

  try {
    final opened = await (launch?.call(uri) ?? _launchExternal(uri));
    if (!opened && context.mounted) {
      _showActionFailure(
        context,
        'Your browser blocked the link. Allow pop-ups and try again.',
      );
    }
    return opened;
  } catch (error, stackTrace) {
    debugPrint('External link failed for $uri: $error\n$stackTrace');
    if (context.mounted) {
      _showActionFailure(
        context,
        "Couldn't open that link. Check the address and try again.",
      );
    }
    return false;
  }
}

Future<bool> _launchExternal(Uri uri) => launchUrl(
  uri,
  mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
  webOnlyWindowName: kIsWeb ? '_blank' : null,
);

void _showActionFailure(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}
