import 'dart:async';

import 'package:earplug/services/user_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clipboard success is announced only after the write resolves', (
    tester,
  ) async {
    final write = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') await write.future;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => copyForUser(
                context,
                'https://earplug.app/g/test',
                successMessage: 'Link copied.',
              ),
              child: const Text('COPY'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('COPY'));
    await tester.pump();
    expect(find.text('Link copied.'), findsNothing);
    write.complete();
    await tester.pump();
    expect(find.text('Link copied.'), findsOne);
  });

  testWidgets('clipboard failure presents a selectable-link fallback', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'blocked');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  copyForUser(context, 'https://earplug.app/static-bloom'),
              child: const Text('COPY'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('COPY'));
    await tester.pumpAndSettle();
    expect(find.text('COPY THIS LINK'), findsOne);
    expect(
      find.widgetWithText(SelectableText, 'https://earplug.app/static-bloom'),
      findsOne,
    );
  });

  testWidgets('external links validate, report blocking, and open valid URLs', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    var launches = 0;
    expect(
      await openExternalForUser(
        context,
        'javascript:alert(1)',
        launch: (_) async {
          launches++;
          return true;
        },
      ),
      isFalse,
    );
    await tester.pump();
    expect(find.text('That link is not a valid web address.'), findsOneWidget);
    expect(launches, 0);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    expect(
      await openExternalForUser(
        context,
        'https://example.com/tickets',
        launch: (uri) async {
          launches++;
          expect(uri.host, 'example.com');
          return false;
        },
      ),
      isFalse,
    );
    await tester.pump();
    expect(find.textContaining('blocked the link'), findsOneWidget);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    expect(
      await openExternalForUser(
        context,
        'https://example.com/tickets',
        launch: (_) async {
          launches++;
          return true;
        },
      ),
      isTrue,
    );
    expect(launches, 2);
  });
}
