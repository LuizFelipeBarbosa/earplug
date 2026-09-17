import 'package:earplug/demo_data.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/search_query.dart';
import 'package:earplug/services/recent_searches.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accessibility.dart';
import 'support/harness.dart';

void main() {
  testWidgets('default view adds recent searches above suggestions', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    expect(find.byKey(const ValueKey('explore-default')), findsOne);
    expect(find.text('RECENT SEARCHES'), findsNothing);
    expect(find.text('SUGGESTIONS'), findsOne);
    expect(find.byType(EpMenuRow), findsNWidgets(3));
    for (final suffix in ['near-me', 'tonight', 'free']) {
      expect(find.byKey(Key('explore-suggest-$suffix')), findsOne);
    }
    expect(find.byType(FanEventCard), findsNothing);

    await tester.tap(find.byKey(const Key('explore-suggest-free')));
    await tester.pumpAndSettle();
    harness.app.setQuery('');
    await tester.pumpAndSettle();

    expect(_recentLabel(tester, 0), 'free');
    expect(
      tester.getTopLeft(find.text('RECENT SEARCHES')).dy,
      lessThan(tester.getTopLeft(find.text('SUGGESTIONS')).dy),
    );
  });

  testWidgets(
    'recent and suggestion rows stay compact with accessible targets',
    (tester) async {
      await pumpApp(
        tester,
        home: const Scaffold(body: ExploreScreen()),
        recentSearchesStore: MemoryRecentSearchesStore(['free']),
      );

      for (final key in [
        'explore-recent-0',
        'explore-suggest-near-me',
        'explore-suggest-tonight',
        'explore-suggest-free',
      ]) {
        final row = find.byKey(Key(key));
        expect(tester.getSize(row).height, inInclusiveRange(44, 52));
      }
      expect(
        tester.getRect(find.byKey(const Key('explore-suggest-near-me'))).top -
            tester.getRect(find.text('SUGGESTIONS')).bottom,
        lessThanOrEqualTo(8),
      );
    },
  );

  testWidgets('recent searches keep the three newest entries in order', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    for (final query in ['Foghorn', 'noise', 'near me', 'free']) {
      await harness.app.recordSearch(query);
    }
    await tester.pumpAndSettle();

    expect(harness.app.recentSearches, ['free', 'near me', 'noise']);
    expect(
      [for (var i = 0; i < 3; i++) _recentLabel(tester, i)],
      ['free', 'near me', 'noise'],
    );
    expect(find.byKey(const Key('explore-recent-3')), findsNothing);
  });

  testWidgets('removing a recent search preserves the other entries', (
    tester,
  ) async {
    final store = MemoryRecentSearchesStore(['free', 'tonight', 'near me']);
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
      recentSearchesStore: store,
    );
    final remove = find.byKey(const Key('explore-recent-clear-1'));
    await tester.scrollUntilVisible(
      remove,
      160,
      scrollable: _scrollable('default'),
    );
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(harness.app.query, isEmpty);
    expect(harness.app.recentSearches, ['free', 'near me']);
    expect(await store.load(), ['free', 'near me']);
    expect(_recentLabel(tester, 0), 'free');
    expect(_recentLabel(tester, 1), 'near me');
    expect(find.byKey(const Key('explore-recent-2')), findsNothing);
  });

  testWidgets('replaying a recent search moves it to the front', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
      recentSearchesStore: MemoryRecentSearchesStore(['free', 'Foghorn']),
    );
    final recent = find.byKey(const Key('explore-recent-1'));
    await tester.scrollUntilVisible(
      recent,
      160,
      scrollable: _scrollable('default'),
    );
    await tester.tap(recent);
    await tester.pumpAndSettle();

    expect(harness.app.query, 'Foghorn');
    expect(harness.app.recentSearches, ['Foghorn', 'free']);
    expect(tester.widget<TextField>(_searchField).controller!.text, 'Foghorn');
    expect(find.byKey(const ValueKey('explore-results')), findsOne);
  });

  for (final suggestion in [
    (key: 'near-me', query: 'near me'),
    (key: 'tonight', query: 'tonight'),
    (key: 'free', query: 'free'),
  ]) {
    testWidgets(
      '${suggestion.query} suggestion searches and records its query',
      (tester) async {
        final harness = await pumpApp(
          tester,
          home: const Scaffold(body: ExploreScreen()),
        );
        final row = find.byKey(Key('explore-suggest-${suggestion.key}'));
        await tester.scrollUntilVisible(
          row,
          160,
          scrollable: _scrollable('default'),
        );
        await tester.tap(row);
        await tester.pumpAndSettle();

        expect(harness.app.query, suggestion.query);
        expect(harness.app.recentSearches, [suggestion.query]);
        expect(
          tester.widget<TextField>(_searchField).controller!.text,
          suggestion.query,
        );
        expect(find.byKey(const ValueKey('explore-results')), findsOne);
      },
    );
  }

  testWidgets(
    'typing filters on every keystroke and submitting records the query',
    (tester) async {
      final store = MemoryRecentSearchesStore();
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: ExploreScreen()),
        recentSearchesStore: store,
      );
      for (final query in ['F', 'Fo', 'Fog', 'Foghorn']) {
        await tester.enterText(_searchField, query);
        await tester.pumpAndSettle();
        expect(harness.app.query, query);
        expect(find.byKey(const ValueKey('explore-results')), findsOne);
        expect(find.text('RIPTIDE RELEASE SHOW'), findsWidgets);
      }
      expect(harness.app.recentSearches, isEmpty);
      expect(await store.load(), isEmpty);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(harness.app.recentSearches, ['Foghorn']);
      expect(await store.load(), ['Foghorn']);

      await tester.enterText(_searchField, 'Foghorn zzz');
      await tester.pumpAndSettle();
      expect(harness.app.query, 'Foghorn zzz');
      expect(find.byKey(const Key('explore-no-results')), findsOne);
      expect(find.text('RIPTIDE RELEASE SHOW'), findsNothing);
    },
  );

  testWidgets('meta line describes a matching genre, time, and free query', (
    tester,
  ) async {
    final tonightGig = DemoData.gigs.firstWhere((gig) => gig.id == 'g1');
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
      now: () => tonightGig.startsAt.subtract(const Duration(hours: 3)),
    );
    await tester.enterText(_searchField, 'hardcore tonight free');
    await tester.pumpAndSettle();

    expect(harness.app.searchResults.map((hit) => hit.gig.id), ['g1']);
    final meta = tester.widget<Text>(
      find.byKey(const Key('explore-results-meta')),
    );
    expect(meta.data, '1 RESULT · TONIGHT · FREE · HARDCORE');
    expect(
      meta.data,
      searchMetaLine(
        harness.app.parsedSearch,
        harness.app.searchResults.length,
      ),
    );
  });

  testWidgets(
    'ranked hits appear as a featured hero followed by compact rows',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: ExploreScreen()),
      );
      harness.app.setQuery('Foghorn');
      await tester.pumpAndSettle();
      final hits = harness.app.searchResults;
      expect(hits.length, greaterThan(1));
      expect(hits.map((hit) => hit.gig.id), containsAll(['g2', 'g7', 'g8']));

      final renderedIds = <String>[];
      var previousOffset = double.negativeInfinity;
      for (var i = 0; i < hits.length; i++) {
        final key = i == 0
            ? 'explore-hero'
            : 'explore-result-${hits[i].gig.id}';
        final row = _eventCard(key);
        await tester.scrollUntilVisible(
          row,
          160,
          scrollable: _scrollable('results'),
        );
        await tester.pumpAndSettle();
        final card = tester.widget<FanEventCard>(row);
        expect(card.rowKey, Key(key));
        expect(card.showDistance, isTrue);
        expect(
          card.presentation,
          i == 0
              ? FanEventCardPresentation.featured
              : FanEventCardPresentation.compact,
        );
        renderedIds.add(card.gig.id);
        final offset =
            tester
                .state<ScrollableState>(_scrollable('results'))
                .position
                .pixels +
            tester.getTopLeft(row).dy;
        expect(offset, greaterThan(previousOffset));
        previousOffset = offset;
      }
      expect(renderedIds, hits.map((hit) => hit.gig.id));
    },
  );

  testWidgets(
    'hero appears only with hits and unmatched queries show the empty state',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: ExploreScreen()),
      );
      for (final query in ['', 'zzzz-no-such-show', 'Foghorn', 'events']) {
        harness.app.setQuery(query);
        await tester.pumpAndSettle();
        final hasHits = harness.app.searchResults.isNotEmpty;
        expect(_eventCard('explore-hero'), hasHits ? findsOne : findsNothing);
        if (query.isNotEmpty && !hasHits) {
          expect(find.byKey(const Key('explore-no-results')), findsOne);
          expect(
            find.text(
              'Nothing matches. Try a band, a venue, a place, or tonight / free.',
            ),
            findsOne,
          );
          expect(find.byType(FanEventCard), findsNothing);
        }
      }
    },
  );

  testWidgets('clear resets the field and query to the default view', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    expect(find.byKey(const Key('explore-search-clear')), findsNothing);
    await tester.enterText(_searchField, 'Foghorn');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-search-clear')));
    await tester.pumpAndSettle();

    expect(harness.app.query, isEmpty);
    expect(tester.widget<TextField>(_searchField).controller!.text, isEmpty);
    expect(find.byKey(const ValueKey('explore-default')), findsOne);
    expect(find.byKey(const ValueKey('explore-results')), findsNothing);
    expect(find.byKey(const Key('explore-search-clear')), findsNothing);
  });

  testWidgets('recent searches persist across fresh AppState instances', (
    tester,
  ) async {
    final store = MemoryRecentSearchesStore();
    final first = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
      recentSearchesStore: store,
    );
    await tester.tap(find.byKey(const Key('explore-suggest-free')));
    await tester.pumpAndSettle();
    expect(first.app.recentSearches, ['free']);

    final second = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
      recentSearchesStore: store,
    );
    expect(identical(first.app, second.app), isFalse);
    expect(second.app.query, isEmpty);
    expect(second.app.recentSearches, ['free']);
    expect(find.text('RECENT SEARCHES'), findsOne);
    expect(_recentLabel(tester, 0), 'free');
  });

  testWidgets(
    'external queries resync the field while local edits preserve selection',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: ExploreScreen()),
        beforePump: (app) => app.setQuery('free'),
      );
      final controller = tester.widget<TextField>(_searchField).controller!;
      expect(controller.text, 'free');
      harness.app.setQuery('Foghorn');
      await tester.pumpAndSettle();
      expect(controller.text, 'Foghorn');
      expect(controller.selection, const TextSelection.collapsed(offset: 7));

      await tester.showKeyboard(_searchField);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Fog horn',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.app.query, 'Fog horn');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
    },
  );

  testWidgets('search border responds to focus with square grammar styling', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: ExploreScreen()));
    final context = tester.element(_searchField);
    BoxDecoration decoration() =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: _searchField,
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is Container &&
                              widget.decoration is BoxDecoration,
                        ),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    expect(
      decoration().border,
      Border.all(color: context.epColors.line, width: 1),
    );
    expect(decoration().borderRadius, isNull);
    await tester.tap(_searchField);
    await tester.pumpAndSettle();
    expect(
      decoration().border,
      Border.all(color: context.epColors.accent, width: 1.5),
    );
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(
      decoration().border,
      Border.all(color: context.epColors.line, width: 1),
    );
  });

  for (final size in [const Size(402, 900), const Size(1280, 900)]) {
    testWidgets('title and search remain fixed while results scroll at $size', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: ExploreScreen()),
        size: size,
      );
      harness.app.setQuery('near me');
      await tester.pumpAndSettle();
      final titleRect = tester.getRect(find.byType(EpDisplay).first);
      final fieldRect = tester.getRect(_searchField);
      await tester.drag(_scrollable('results'), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(_scrollable('results')).position.pixels,
        greaterThan(0),
      );
      expect(tester.getRect(find.byType(EpDisplay).first), titleRect);
      expect(tester.getRect(_searchField), fieldRect);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search content is vertically centered at 1.0x text scale', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: ExploreScreen()));
    _expectSearchContentCentered(tester, hasText: false);

    await tester.enterText(_searchField, 'Foghorn');
    await tester.pumpAndSettle();
    _expectSearchContentCentered(tester, hasText: true);
  });

  testWidgets('search content is vertically centered at 1.5x text scale', (
    tester,
  ) async {
    await pumpApp(tester, home: scaledScreen(const ExploreScreen()));
    _expectSearchContentCentered(tester, hasText: false);

    await tester.enterText(_searchField, 'Foghorn');
    await tester.pumpAndSettle();
    _expectSearchContentCentered(tester, hasText: true);
  });
}

Finder get _searchField => find.byKey(const Key('explore-search-field'));

String _recentLabel(WidgetTester tester, int index) =>
    tester.widget<EpMenuRow>(find.byKey(Key('explore-recent-$index'))).label;

Finder _eventCard(String key) => find.byWidgetPredicate(
  (widget) => widget is FanEventCard && widget.key == Key(key),
);

Finder _scrollable(String mode) => find.descendant(
  of: find.byKey(ValueKey('explore-$mode')),
  matching: find.byType(Scrollable),
);

void _expectSearchContentCentered(
  WidgetTester tester, {
  required bool hasText,
}) {
  final container = find
      .ancestor(
        of: _searchField,
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration is BoxDecoration,
        ),
      )
      .first;
  final centerY = tester.getRect(container).center.dy;
  final editable = find.descendant(
    of: _searchField,
    matching: find.byType(EditableText),
  );
  expect(tester.getRect(editable).center.dy, closeTo(centerY, 1));
  expect(
    tester.getRect(find.byIcon(Icons.search)).center.dy,
    closeTo(centerY, 1),
  );
  if (hasText) {
    expect(
      tester.getRect(find.byKey(const Key('explore-search-clear'))).center.dy,
      closeTo(centerY, 1),
    );
  } else {
    final hint = find.descendant(
      of: _searchField,
      matching: find.text('Events, bands, venues, places, tonight, free…'),
    );
    expect(tester.getRect(hint).center.dy, closeTo(centerY, 1));
  }
}
