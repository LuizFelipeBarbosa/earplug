import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

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
