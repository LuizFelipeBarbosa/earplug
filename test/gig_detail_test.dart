import 'dart:async';
import 'dart:ui' as ui;

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/flyer_styles.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/venue_mini_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  setUpAll(() async {
    // Use the app's fonts so text wrapping and the fixed CTA match production.
    final telegraf = FontLoader('PP Telegraf')
      ..addFont(rootBundle.load('assets/fonts/PPTelegraf-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/PPTelegraf-Ultrabold.otf'));
    await telegraf.load();
    final mono = FontLoader('Azeret Mono')
      ..addFont(rootBundle.load('assets/fonts/AzeretMono-Regular.ttf'));
    await mono.load();
  });

  testWidgets('flyer hero starts at the top and overlays the header controls', (
    tester,
  ) async {
    const size = Size(402, 900);
    final harness = await pumpApp(
      tester,
      size: size,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g1')),
    );
    final gig = harness.app.gig('g1')!;
    final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
    final flyerRect = tester.getRect(flyer);
    expect(flyerRect.top, 0);
    expect(flyerRect.width, 402);
    expect(flyerRect.height, 402 * 1.25);
    expect(
      find.descendant(of: flyer, matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(of: flyer, matching: find.byType(EpIconPill)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('gig-detail-hero-content')), findsOne);
    for (final key in [
      'gig-detail-back-control',
      'gig-detail-save-g1',
      'gig-detail-share-g1',
    ]) {
      final control = find.byKey(ValueKey(key));
      expect(control, findsOne);
      expect(tester.getSize(control), const Size(44, 44));
      expect(control.hitTestable(), findsOne);
      expect(tester.widget<ExploreCardIconButton>(control).circle, isTrue);
      final controlRect = tester.getRect(control);
      expect(flyerRect.contains(controlRect.topLeft), isTrue);
      expect(flyerRect.contains(controlRect.bottomRight), isTrue);
    }
    final header = find.byKey(const ValueKey('gig-detail-header-bar'));
    final titleFade = find.descendant(
      of: header,
      matching: find.byType(Opacity),
    );
    expect(tester.getTopLeft(header).dy, 0);
    expect(tester.getSize(header).height, 44 + EpLayout.gutter * 2);
    final back = find.byKey(const ValueKey('gig-detail-back-control'));
    final share = find.byKey(const ValueKey('gig-detail-share-g1'));
    expect(tester.getTopLeft(back).dy, EpLayout.gutter);
    expect(tester.getTopLeft(back).dx, EpLayout.gutter);
    expect(tester.getTopRight(share).dx, size.width - EpLayout.gutter);
    expect(tester.widget<Opacity>(titleFade).opacity, 0.0);
    final restingDecoration =
        tester.widget<Container>(header).decoration! as BoxDecoration;
    final restingForeground =
        tester.widget<Container>(header).foregroundDecoration! as BoxDecoration;
    expect(restingDecoration.color!.a, 0);
    expect((restingForeground.border! as Border).bottom.color.a, 0);
    final placeholder = find.descendant(
      of: flyer,
      matching: find.byKey(const ValueKey('gig-detail-flyer-placeholder')),
    );
    expect(placeholder, findsNothing);
    final pressPanel = find.descendant(
      of: flyer,
      matching: find.byType(FittedBox),
    );
    expect(pressPanel, findsOne);
    expect(tester.widget<FittedBox>(pressPanel).fit, BoxFit.contain);
    final press = find.descendant(
      of: pressPanel,
      matching: find.byType(GigFlyer),
    );
    expect(press, findsOne);
    expect(tester.widget<GigFlyer>(press).style, flyerStyles['paper']);
    expect(tester.getSize(press), const Size(240, 300));
    final blur = find.descendant(
      of: flyer,
      matching: find.byType(ImageFiltered),
    );
    expect(blur, findsOne);
    expect(tester.widget<ImageFiltered>(blur).child, isA<GigFlyer>());
    final scrim = tester.widgetList<ColoredBox>(
      find.descendant(of: flyer, matching: find.byType(ColoredBox)),
    );
    expect(
      scrim.any(
        (box) =>
            box.color ==
            tester.element(flyer).epColors.background.withValues(alpha: .55),
      ),
      isTrue,
    );

    final title = find.byKey(const ValueKey('gig-detail-title-block'));
    expect(tester.getTopLeft(title).dy - flyerRect.bottom, closeTo(24, 1));
    final display = tester.widget<EpDisplay>(
      find.descendant(of: title, matching: find.byType(EpDisplay)),
    );
    expect(display.text, gig.title);
    expect(display.size, 32);
    expect(display.maxLines, 3);
    expect(
      find.descendant(of: title, matching: find.byType(EpEyebrow)),
      findsNothing,
    );
    final date = find.byKey(const Key('gig-fact-date'));
    expect(
      find.descendant(of: date, matching: find.text(gig.dateShort)),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('gig-fact-times')),
        matching: find.text('Doors 8PM · Start 9PM'),
      ),
      findsOne,
    );
    final times = tester.widget<Text>(find.text('Doors 8PM · Start 9PM'));
    expect(times.maxLines, 1);
    expect(times.overflow, TextOverflow.ellipsis);
    expect(
      tester.getTopLeft(find.text('Doors 8PM · Start 9PM')).dy -
          tester.getBottomLeft(find.text(gig.dateShort)).dy,
      closeTo(4, 1),
    );
    final meta = find.byKey(const Key('gig-fact-meta'));
    final free = find.descendant(of: meta, matching: find.text('FREE'));
    expect(
      tester.widget<Text>(free).style?.color,
      tester.element(meta).epColors.accent,
    );
    expect(find.descendant(of: meta, matching: find.text('18+')), findsOne);
    expect(
      find.descendant(of: meta, matching: find.textContaining('GOING')),
      findsNothing,
    );
    expect(
      tester
          .widgetList<Text>(
            find.descendant(of: meta, matching: find.byType(Text)),
          )
          .map((text) => text.style?.fontSize),
      everyElement(15),
    );
    expect(find.byType(EpFactGrid), findsNothing);
    expect(find.byType(EpFactCell), findsNothing);
    expect(find.byType(EpPanel), findsNothing);

    final cta = find.byType(EpBottomCta);
    expect(
      find.descendant(
        of: cta,
        matching: find.text('FREE · RSVP FOR HEADCOUNT'),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: cta, matching: find.byType(EpEyebrow)),
      findsOne,
    );
    final button = find.descendant(of: cta, matching: find.byType(EpPill));
    expect(tester.widget<EpPill>(button).variant, EpPillVariant.primary);
    expect(tester.widget<EpPill>(button).expand, isTrue);
    expect(tester.getSize(button).width, tester.getSize(cta).width - 40);
    expect(tester.getRect(cta).bottom, 900);

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    final colors = tester.element(header).epColors;
    for (final offset in [40.0, 160.0]) {
      controller.jumpTo(offset);
      await tester.pump();

      final progress = (offset / 80).clamp(0.0, 1.0);
      expect(tester.widget<Opacity>(titleFade).opacity, progress);
      final headerTitle = find.descendant(
        of: titleFade,
        matching: find.text(gig.title.toUpperCase()),
      );
      expect(headerTitle.hitTestable(), findsOne);
      expect(tester.widget<Text>(headerTitle).maxLines, 1);
      final decoration =
          tester.widget<Container>(header).decoration! as BoxDecoration;
      final foreground =
          tester.widget<Container>(header).foregroundDecoration!
              as BoxDecoration;
      expect(
        decoration.color,
        Color.lerp(
          colors.background.withValues(alpha: 0),
          colors.background,
          progress,
        ),
      );
      expect(
        (foreground.border! as Border).bottom.color,
        Color.lerp(colors.line.withValues(alpha: 0), colors.line, progress),
      );
      expect(tester.getTopLeft(header).dy, 0);
      expect(tester.getRect(cta).bottom, 900);
    }

    controller.jumpTo(0);
    tester.view.padding = const FakeViewPadding(top: 47);
    await tester.pump();
    expect(tester.getTopLeft(flyer).dy, 0);
    expect(tester.getSize(flyer).height, 47 + 402 * 1.25);
    expect(tester.getTopLeft(press).dy, 47);
    expect(tester.getSize(pressPanel).height, 402 * 1.25);
    expect(tester.getSize(header).height, 44 + EpLayout.gutter * 2 + 47);
    expect(tester.widget<Opacity>(titleFade).opacity, 0.0);
    expect(tester.getTopLeft(back).dy, 47 + EpLayout.gutter);
    expect(tester.getTopLeft(back).dx, EpLayout.gutter);
    expect(tester.getTopRight(share).dx, size.width - EpLayout.gutter);
  });

  testWidgets('unknown flyer keys keep the neutral hero placeholder', (
    tester,
  ) async {
    await _pumpPresentation(
      tester,
      gigFixture(id: 'legacy-flyer', flyKey: 'legacy-removed'),
    );

    final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
    final placeholder = find.descendant(
      of: flyer,
      matching: find.byKey(const ValueKey('gig-detail-flyer-placeholder')),
    );
    expect(placeholder, findsOne);
    expect(
      find.descendant(of: flyer, matching: find.byType(GigFlyer)),
      findsNothing,
    );
    expect(
      tester.widget<Container>(placeholder).color,
      tester.element(flyer).epColors.panel,
    );
    expect(
      find.descendant(
        of: placeholder,
        matching: find.byIcon(Icons.image_outlined),
      ),
      findsOne,
    );
    final blur = find.descendant(
      of: flyer,
      matching: find.byType(ImageFiltered),
    );
    expect(blur, findsOne);
    expect(tester.widget<ImageFiltered>(blur).child, isA<ColoredBox>());

    tester.view.padding = const FakeViewPadding(top: 47);
    await tester.pump();
    expect(tester.getTopLeft(placeholder).dy, 47);
    expect(tester.getSize(placeholder).height, 402 * 1.25);
  });

  testWidgets('draft preview contains the press design without cropping', (
    tester,
  ) async {
    await _pumpPresentation(
      tester,
      gigFixture(id: 'press-preview', flyKey: 'accent'),
      previewLabel: 'PRIVATE DRAFT',
      size: const Size(402, 600),
    );

    final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
    expect(tester.getSize(flyer), const Size(402, 360));
    expect(
      find.byKey(const ValueKey('gig-detail-flyer-placeholder')),
      findsNothing,
    );
    final pressPanel = find.descendant(
      of: flyer,
      matching: find.byType(FittedBox),
    );
    expect(tester.widget<FittedBox>(pressPanel).fit, BoxFit.contain);
    final press = find.descendant(
      of: pressPanel,
      matching: find.byType(GigFlyer),
    );
    expect(press, findsOne);
    expect(tester.widget<GigFlyer>(press).style, flyerStyles['accent']);
    expect(tester.getSize(press), const Size(240, 300));
    // The capped content height leaves equal space beside the 4:5 press.
    expect(tester.getTopLeft(press), const Offset(57, 0));
    expect(tester.getBottomRight(press), const Offset(345, 360));
    final blur = find.descendant(
      of: flyer,
      matching: find.byType(ImageFiltered),
    );
    final backdrop = find.descendant(of: blur, matching: find.byType(GigFlyer));
    expect(backdrop, findsOne);
    expect(tester.widget<GigFlyer>(backdrop).style, flyerStyles['accent']);
    expect(tester.getRect(backdrop), tester.getRect(flyer));
  });

  testWidgets(
    'title row offers calendar and directions icons for an exact venue',
    (tester) async {
      final launches = _recordExternalLaunches(tester);
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: GigDetailScreen(gigId: 'g3')),
      );
      final header = find.byKey(const ValueKey('gig-detail-header-bar'));
      final title = find.byKey(const ValueKey('gig-detail-title-block'));
      final titleText = find.descendant(
        of: title,
        matching: find.byType(Column),
      );
      for (final key in ['gig-add-to-calendar', 'gig-venue-directions']) {
        expect(
          find.descendant(of: header, matching: find.byKey(ValueKey(key))),
          findsNothing,
        );
        final control = find.descendant(
          of: title,
          matching: find.byKey(ValueKey(key)),
        );
        expect(control, findsOne);
        expect(tester.widget<ExploreCardIconButton>(control).ring, isTrue);
        expect(tester.widget<ExploreCardIconButton>(control).circle, isFalse);
        expect(tester.getSize(control), const Size(44, 44));
        expect(control.hitTestable(), findsOne);
        expect(tester.getTopLeft(control).dy, tester.getTopLeft(title).dy);
        expect(tester.getTopLeft(control).dy, tester.getTopLeft(titleText).dy);
      }
      final controls = [
        for (final key in [
          'gig-detail-back-control',
          'gig-detail-save-g3',
          'gig-detail-share-g3',
        ])
          tester.getRect(
            find.descendant(of: header, matching: find.byKey(ValueKey(key))),
          ),
      ];
      for (var index = 1; index < controls.length; index++) {
        expect(controls[index].left, greaterThan(controls[index - 1].right));
      }
      final calendar = find.descendant(
        of: title,
        matching: find.byKey(const ValueKey('gig-add-to-calendar')),
      );
      final directions = find.descendant(
        of: title,
        matching: find.byKey(const ValueKey('gig-venue-directions')),
      );
      expect(
        tester.getTopLeft(directions).dx - tester.getTopRight(calendar).dx,
        8,
      );
      expect(tester.getTopRight(directions).dx, tester.getTopRight(title).dx);
      await tester.tap(directions);
      await tester.pump();
      final venue = harness.app.venue(harness.app.gig('g3')!.venueId);
      expect(
        launches.single.toString(),
        'https://www.google.com/maps/search/?api=1&query=${venue.point.latitude},${venue.point.longitude}',
      );
    },
  );

  for (final gigId in ['g1', 'g2']) {
    testWidgets('title row opens a calendar with readable names for $gigId', (
      tester,
    ) async {
      final launches = _recordExternalLaunches(tester);
      final harness = await pumpApp(
        tester,
        home: Scaffold(body: GigDetailScreen(gigId: gigId)),
      );
      final gig = harness.app.gig(gigId)!;
      final calendar = find.descendant(
        of: find.byKey(const ValueKey('gig-detail-title-block')),
        matching: find.byKey(const ValueKey('gig-add-to-calendar')),
      );
      expect(calendar, findsOne);
      expect(tester.widget<ExploreCardIconButton>(calendar).ring, isTrue);
      final target = find.descendant(
        of: calendar,
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(target), const Size(44, 44));
      await tester.ensureVisible(calendar);
      await tester.pumpAndSettle();
      // Tap near the top edge of the 44px target, outside the 36px ring.
      final rect = tester.getRect(target);
      await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
      await tester.pump();

      final url = launches.single;
      expect(url.host, 'calendar.google.com');
      expect(url.queryParameters['text'], gig.title);
      if (gig.createdByBand != null) {
        expect(
          url.queryParameters['details'],
          startsWith(
            'Presented by ${harness.app.band(gig.createdByBand!)!.name}',
          ),
        );
        expect(
          url.queryParameters['details'],
          isNot(contains(gig.createdByBand!)),
        );
      } else {
        final names = gig.lineup
            .map((id) => harness.app.band(id)!.name)
            .join(', ');
        expect(url.queryParameters['details'], startsWith('Lineup: $names'));
      }
    });
  }

  testWidgets(
    'calendar for an unset venue uses text lineup names and no location',
    (tester) async {
      final launches = _recordExternalLaunches(tester);
      await _pumpPresentation(
        tester,
        _textOnlyGig().copyWith(createdByBand: 'unresolved-band'),
        venueSet: false,
      );
      final calendar = find.descendant(
        of: find.byKey(const ValueKey('gig-detail-title-block')),
        matching: find.byKey(const ValueKey('gig-add-to-calendar')),
      );
      await tester.ensureVisible(calendar);
      await tester.pumpAndSettle();
      await tester.tap(calendar);
      await tester.pump();
      expect(
        launches.single.queryParameters['details'],
        'Lineup: Text Only Opener',
      );
      expect(launches.single.queryParameters, isNot(contains('location')));
    },
  );

  testWidgets('lineup genre text stays on one line with ellipsis', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(320, 900),
      home: const Scaffold(body: GigDetailScreen(gigId: 'g2')),
    );
    final row = find
        .descendant(
          of: find.byKey(const ValueKey('gig-lineup')),
          matching: find.byType(EpEntityRow),
        )
        .first;
    final sub = tester.widget<EpEntityRow>(row).sub!;
    expect(sub, contains('surf punk'));
    final subtitle = find.descendant(of: row, matching: find.text(sub));
    final text = tester.widget<Text>(subtitle);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    final painter = TextPainter(
      text: TextSpan(text: sub, style: text.style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(painter.width, greaterThan(tester.getSize(subtitle).width));
    painter.dispose();
  });

  testWidgets(
    'sections have 24px gaps except for 12px between title and facts',
    (tester) async {
      await _pumpPresentation(tester, _textOnlyGig(desc: '   '));
      expect(find.text('ABOUT'), findsNothing);
      final hidden = find.byKey(
        const ValueKey('gig-attendance-hidden-shared-gig'),
      );
      expect(tester.getSize(hidden).height, 0);
      final sections = [
        find.byKey(const ValueKey('gig-detail-flyer')),
        find.byKey(const ValueKey('gig-detail-title-block')),
        find.byKey(const Key('gig-facts')),
        find.byKey(const ValueKey('gig-lineup')),
        find.byKey(const Key('gig-venue-card')),
      ];
      for (var index = 1; index < sections.length; index++) {
        expect(
          tester.getTopLeft(sections[index]).dy -
              tester.getBottomLeft(sections[index - 1]).dy,
          closeTo(index == 2 ? 12 : 24, 1),
          reason: 'Gap before section $index',
        );
      }
      final facts = sections[2];
      final children = tester.widget<Column>(facts).children;
      expect(
        tester.getTopLeft(facts).dy,
        tester.getTopLeft(find.byWidget(children.first)).dy,
      );
      expect(
        tester.getBottomLeft(facts).dy,
        tester.getBottomLeft(find.byWidget(children.last)).dy,
      );
    },
  );

  testWidgets(
    'venue card clears the sticky CTA by at least 48px at scroll end',
    (tester) async {
      const size = Size(402, 900);
      await _pumpPresentation(tester, _textOnlyGig(), size: size);
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(controller.offset, controller.position.maxScrollExtent);
      final venueCard = find.byKey(const Key('gig-venue-card'));
      final venueRect = tester.getRect(venueCard);
      final clearance = actionBarClearance(tester.element(venueCard));
      expect(
        venueRect.bottom,
        lessThanOrEqualTo(size.height - clearance - 48),
      );
    },
  );

  testWidgets('About has one 24px gap on either side', (tester) async {
    final gig = _textOnlyGig();
    await _pumpPresentation(tester, gig);
    final about = find.widgetWithText(EpSectionHeader, 'ABOUT');
    final lineup = find.byKey(const ValueKey('gig-lineup'));
    final card = find.byKey(const Key('gig-venue-card'));
    expect(
      tester.getTopLeft(about).dy - tester.getBottomLeft(lineup).dy,
      closeTo(24, 1),
    );
    expect(tester.widget<EpSectionHeader>(about).padding.top, 0);
    expect(
      tester.getTopLeft(card).dy - tester.getBottomLeft(find.text(gig.desc)).dy,
      closeTo(24, 1),
    );
  });

  testWidgets('preview venue card has no directions action', (tester) async {
    await _pumpPresentation(
      tester,
      _textOnlyGig(),
      previewLabel: 'PRIVATE DRAFT',
    );
    final card = find.byKey(const Key('gig-venue-card'));
    final tap = find.descendant(of: card, matching: find.byType(InkWell));
    expect(tester.widget<InkWell>(tap).onTap, isNull);
    final title = find.byKey(const ValueKey('gig-detail-title-block'));
    for (final key in ['gig-add-to-calendar', 'gig-venue-directions']) {
      expect(
        find.descendant(of: title, matching: find.byKey(ValueKey(key))),
        findsNothing,
      );
    }
    expect(find.byKey(const Key('gig-venue-directions')), findsNothing);
    expect(find.byKey(const Key('gig-venue-card-directions')), findsNothing);
    expect(
      find.descendant(of: card, matching: find.textContaining('AREA ONLY')),
      findsOne,
    );
  });

  testWidgets(
    'portrait custom flyer uses blur and contain with preview status below the flyer',
    (tester) async {
      final gig = gigFixture(id: 'draft-preview', title: 'Current draft');
      final portraitBytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 20, 40),
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(20, 40);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      await _pumpPresentation(
        tester,
        gig,
        flyerBytes: portraitBytes!,
        previewLabel: 'PRIVATE DRAFT',
        size: const Size(402, 600),
      );

      final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
      expect(tester.getSize(flyer), const Size(402, 360));
      expect(
        find.descendant(of: flyer, matching: find.byType(ImageFiltered)),
        findsOne,
      );
      final images = tester.widgetList<Image>(
        find.descendant(of: flyer, matching: find.byType(Image)),
      );
      expect(images.map((image) => image.fit), [BoxFit.cover, BoxFit.contain]);
      expect(images.every((image) => image.image is MemoryImage), isTrue);
      expect(
        find.descendant(of: flyer, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byType(GigFlyer), findsNothing);
      final status = find.byKey(const ValueKey('gig-draft-preview-status'));
      expect(tester.getSize(status).height, 32);
      expect(tester.getTopLeft(status).dx, EpLayout.gutter);
      expect(
        tester.getSize(status).width,
        lessThan(tester.getSize(flyer).width),
      );
      expect(
        tester.getTopLeft(status).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(flyer).dy),
      );
      expect(find.byKey(const ValueKey('gig-detail-back-control')), findsOne);
      expect(
        find.byKey(const ValueKey('gig-detail-save-draft-preview')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('gig-detail-share-draft-preview')),
        findsNothing,
      );
      expect(find.text('CURRENT DRAFT'), findsOne);
      expect(find.text('FREE RSVP · PREVIEW ONLY'), findsOne);

      tester.view.padding = const FakeViewPadding(top: 47);
      await tester.pump();
      expect(tester.getTopLeft(flyer).dy, 0);
      expect(tester.getSize(flyer), const Size(402, 407));
      final insetImages = find.descendant(
        of: flyer,
        matching: find.byType(Image),
      );
      expect(tester.getRect(insetImages.first), tester.getRect(flyer));
      expect(tester.getTopLeft(insetImages.last).dy, 47);
      expect(tester.getSize(insetImages.last), const Size(402, 360));
      expect(tester.getSize(status).height, 32);
    },
  );

  testWidgets(
    'remote custom flyer uses plain fallbacks and a sharp contain image',
    (tester) async {
      await _pumpPresentation(
        tester,
        gigFixture(
          id: 'custom',
          flyKey: 'custom',
          flyerUrl: 'https://example.test/flyer.png',
        ),
      );

      final flyer = find.byKey(const ValueKey('gig-detail-flyer'));
      expect(
        find.descendant(of: flyer, matching: find.byType(ImageFiltered)),
        findsOne,
      );
      final images = tester.widgetList<EpNetworkImage>(
        find.descendant(of: flyer, matching: find.byType(EpNetworkImage)),
      );
      expect(images.map((image) => image.fit), [BoxFit.cover, BoxFit.contain]);
      expect(images.every((image) => image.fallback is ColoredBox), isTrue);
      expect(
        find.descendant(of: flyer, matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byType(GigFlyer), findsNothing);
    },
  );

  testWidgets(
    'single-time drafts omit Start and keep an unset venue inactive',
    (tester) async {
      await _pumpPresentation(
        tester,
        gigFixture(
          id: 'single-time',
          time: '8PM',
          createdByBand: 'missing-band',
        ),
        venueSet: false,
        previewLabel: 'PRIVATE DRAFT',
      );
      final date = find.byKey(const Key('gig-fact-date'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('gig-fact-times')),
          matching: find.text('Doors 8PM'),
        ),
        findsOne,
      );
      expect(
        find.descendant(of: date, matching: find.textContaining('Start')),
        findsNothing,
      );
      expect(find.byKey(const Key('gig-venue-card')), findsNothing);
      final title = find.byKey(const ValueKey('gig-detail-title-block'));
      expect(
        find.descendant(of: title, matching: find.byType(EpEyebrow)),
        findsNothing,
      );
    },
  );

  for (final scenario in [
    (gigId: 'g2', area: 'Mission', approximate: true),
    (gigId: 'g3', area: 'Temescal, Oakland', approximate: false),
    (gigId: 'g4', area: 'Dogpatch, SF', approximate: false),
  ]) {
    testWidgets('venue card reflects venue precision for ${scenario.gigId}', (
      tester,
    ) async {
      final launches = _recordExternalLaunches(tester);
      final harness = await pumpApp(
        tester,
        home: Scaffold(body: GigDetailScreen(gigId: scenario.gigId)),
      );
      final venueId = harness.app.gig(scenario.gigId)!.venueId;
      final venue = harness.app.venue(venueId);
      final card = find.byKey(const Key('gig-venue-card'));
      final map = find.descendant(
        of: card,
        matching: find.byType(VenueMapPreview),
      );
      expect(tester.getSize(map), const Size(96, 96));
      expect(
        tester.widget<VenueMapPreview>(map).approximate,
        scenario.approximate,
      );
      expect(tester.widget<VenueMapPreview>(map).showAttribution, isFalse);
      expect(tester.widget<VenueMapPreview>(map).overlayLabel, isNull);
      expect(
        find.descendant(
          of: card,
          matching: find.text(scenario.area.toUpperCase()),
        ),
        findsOne,
      );
      expect(find.byKey(const Key('gig-venue-verified')), findsNothing);
      expect(
        find.textContaining('AREA ONLY'),
        scenario.approximate ? findsOne : findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('gig-detail-title-block')),
          matching: find.byKey(const ValueKey('gig-venue-directions')),
        ),
        scenario.approximate ? findsNothing : findsOne,
      );
      final directions = find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('gig-venue-card-directions')),
      );
      expect(directions, scenario.approximate ? findsNothing : findsOne);
      expect(find.byType(EpPanel), findsNothing);
      expect(find.byType(EpFactGrid), findsNothing);
      final decoration =
          tester.widget<Container>(card).decoration! as BoxDecoration;
      expect(decoration.color, tester.element(card).epColors.panel);
      expect(
        decoration.border,
        Border.all(color: tester.element(card).epColors.line),
      );
      expect(decoration.borderRadius, isNull);
      expect(
        find.descendant(
          of: card,
          matching: find.text(venue.name.toUpperCase()),
        ),
        findsOne,
      );
      final distance = harness.app.distanceOf(venue);
      if (distance.isNotEmpty) {
        expect(
          find.descendant(
            of: card,
            matching: find.text(distance.toUpperCase()),
          ),
          findsOne,
        );
      }
      await Scrollable.ensureVisible(tester.element(card), alignment: .5);
      await tester.pumpAndSettle();
      if (!scenario.approximate) {
        final address = find.descendant(
          of: card,
          matching: find.text(venue.exactAddress!.toUpperCase()),
        );
        expect(address, findsOne);
        expect(tester.widget<Text>(address).maxLines, 1);
        expect(tester.widget<Text>(address).overflow, TextOverflow.ellipsis);
        expect(tester.widget<ExploreCardIconButton>(directions).ring, isTrue);
        final target = find.descendant(
          of: directions,
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(target), const Size(44, 44));
        final routeBefore = harness.app.current;
        await tester.tap(directions);
        await tester.pump();
        expect(
          launches.single.toString(),
          'https://www.google.com/maps/search/?api=1&query=${venue.point.latitude},${venue.point.longitude}',
        );
        expect(harness.app.current, same(routeBefore));
      }
      await tester.tap(
        find.descendant(
          of: card,
          matching: find.text(scenario.area.toUpperCase()),
        ),
      );
      await tester.pump();
      expect(harness.app.current.screen, Screen.venue);
      expect(harness.app.current.param, venueId);
    });
  }

  testWidgets(
    'direct gig subscription keeps cancellations visible and text performers in the lineup',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ControlledPublicGigRepository(auth: auth);
      final published = _textOnlyGig();
      final harness = await pumpApp(
        tester,
        repository: repository,
        home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
        beforePump: (app) {
          repository.emit(published);
          app.openGig('shared-gig');
        },
        pumpFor: const Duration(milliseconds: 100),
      );

      expect(find.text('THIS GIG HAS BEEN CANCELLED'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(EpEntityRow),
          matching: find.text('TEXT ONLY OPENER'),
        ),
        findsOne,
      );
      expect(find.text('RSVP'), findsOne);

      expect(find.byKey(const ValueKey('gig-detail-hero-content')), findsOne);
      expect(
        find.descendant(of: find.byType(GigFlyer), matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.text('LINEUP · 1'), findsOne);

      repository.emit(_textOnlyGig(lifecycle: GigLifecycle.cancelled));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(harness.app.gig('shared-gig')?.lifecycle, GigLifecycle.cancelled);
      expect(find.text('THIS GIG HAS BEEN CANCELLED'), findsOne);
      expect(
        tester.getTopLeft(find.text('THIS GIG HAS BEEN CANCELLED')).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(find.byKey(const ValueKey('gig-detail-flyer')))
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('THIS GIG HAS BEEN CANCELLED')).dx,
        EpLayout.gutter + 14 + 1, // The banner keeps its padding and border.
      );
      expect(find.text('GIG CANCELLED'), findsOne);
    },
  );

  testWidgets('resolved presenter and lineup bands use real profile actions', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g2')),
    );

    expect(find.text('FOGHORN DIET PRESENTS'), findsOne);
    expect(find.textContaining('IN-STORE RACKET'), findsNothing);
    final title = find.byKey(const ValueKey('gig-detail-title-block'));
    expect(
      find.descendant(of: title, matching: find.text('RIPTIDE RELEASE SHOW')),
      findsOne,
    );
    expect(
      find.descendant(of: title, matching: find.text('FOGHORN DIET')),
      findsNothing,
    );
    expect(find.text('PAY AT THE DOOR · RSVP HOLDS NOTHING'), findsOne);
    final meta = find.byKey(const Key('gig-fact-meta'));
    final price = find.descendant(of: meta, matching: find.text(r'$10'));
    expect(
      tester.widget<Text>(price).style?.color,
      tester.element(meta).epColors.ink,
    );
    expect(
      find.descendant(of: meta, matching: find.text('ALL AGES')),
      findsOne,
    );
    expect(find.text('LINEUP · 2'), findsOne);
    final rows = tester
        .widgetList<EpEntityRow>(find.byType(EpEntityRow))
        .toList();
    expect(rows.map((row) => row.title), ['Foghorn Diet', 'Pigeon Court']);
    expect(rows.first.leading, isA<BandAvatar>());
    expect(rows.first.sub, startsWith('Headliner · '));
    expect(rows.last.sub, startsWith('Support · '));
    final firstRow = find.byWidget(rows.first);
    final lastRow = find.byWidget(rows.last);
    final firstBottom = tester.getBottomLeft(firstRow).dy;
    final lastTop = tester.getTopLeft(lastRow).dy;
    expect(lastTop - firstBottom, 1);
    expect(
      find.byType(EpHairline).evaluate().where((element) {
        final rect = tester.getRect(
          find.byElementPredicate((candidate) => identical(candidate, element)),
        );
        return rect.top == firstBottom && rect.bottom == lastTop;
      }),
      hasLength(1),
    );

    final follow = find.byKey(const ValueKey('gig-lineup-follow-b1'));
    await tester.ensureVisible(follow);
    await tester.pumpAndSettle();
    await tester.tap(follow);
    await tester.pump();

    expect(harness.app.pending?.kind, PendingKind.follow);
    expect(harness.app.pending?.id, 'b1');
  });

  testWidgets('gigs without descriptions omit the empty About section', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledPublicGigRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
      beforePump: (app) {
        repository.emit(_textOnlyGig(desc: '   '));
        app.openGig('shared-gig');
      },
      pumpFor: const Duration(milliseconds: 100),
    );

    expect(harness.app.gig('shared-gig'), isNotNull);
    expect(find.text('ABOUT'), findsNothing);
    expect(find.byKey(const Key('gig-venue-card')), findsOne);
  });

  testWidgets(
    'attendance reconciles optimistic changes with confirmed capacity totals',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _AttendanceRepository(
        auth: auth,
        gig: _textOnlyGig(going: 23, cap: '80'),
      );
      addTearDown(repository.close);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
        beforePump: (app) => app.openGig('shared-gig'),
      );

      expect(find.text("WHO'S GOING"), findsNothing);
      expect(find.textContaining('GOING'), findsNothing);
      expect(
        find.byKey(const ValueKey('gig-attendance-hidden-shared-gig')),
        findsOne,
      );

      await tester.tap(find.text('RSVP'));
      await tester.pump();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(
        find.descendant(
          of: find.byKey(const Key('gig-fact-meta')),
          matching: find.textContaining('GOING'),
        ),
        findsNothing,
      );
      expect(find.text("WHO'S GOING"), findsNothing);

      repository.completeMutation();
      await tester.pumpAndSettle();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(find.text("WHO'S GOING"), findsOne);
      expect(find.text('24+ GOING'), findsOne);
      final attendance = find.byKey(
        const ValueKey('gig-attendance-shared-gig'),
      );
      expect(attendance, findsOne);
      expect(find.byKey(const ValueKey('who-is-going-shared-gig')), findsOne);
      expect(find.byType(EpCard), findsNothing);
      expect(
        tester.getBottomLeft(find.byKey(const Key('gig-fact-meta'))).dy,
        lessThan(tester.getTopLeft(find.text("WHO'S GOING")).dy),
      );
      expect(
        tester.getTopLeft(attendance).dy -
            tester.getBottomLeft(find.byKey(const ValueKey('gig-lineup'))).dy,
        closeTo(0, 1),
      );
      expect(
        tester.getTopLeft(find.text("WHO'S GOING")).dy -
            tester.getTopLeft(attendance).dy,
        closeTo(24, 1),
      );
      final attendanceDivider = find
          .descendant(of: attendance, matching: find.byType(EpHairline))
          .last;
      expect(
        tester.getTopLeft(find.widgetWithText(EpSectionHeader, 'ABOUT')).dy -
            tester.getBottomLeft(attendanceDivider).dy,
        closeTo(24, 1),
      );
      expect(find.text('24 of 80 spots filled'), findsOne);
      final progress = find.descendant(
        of: find.byKey(
          const ValueKey('attendance-capacity-progress-shared-gig'),
        ),
        matching: find.byType(LinearProgressIndicator),
      );
      expect(tester.widget<LinearProgressIndicator>(progress).value, .3);
      await tester.scrollUntilVisible(
        find.text('24 of 80 spots filled'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.bySemanticsLabel('24 of 80 spots filled'), findsOne);
      expect(
        find.textContaining('Bands you follow on this bill'),
        findsNothing,
      );
      expect(find.textContaining('Attendance stays vague'), findsNothing);
      expect(find.text('YOU MAY KNOW'), findsNothing);

      repository.emitGoing(25);
      await tester.pumpAndSettle();
      expect(harness.app.rsvpCount(repository.gig), 25);
      expect(find.text('25 of 80 spots filled'), findsOne);
      expect(
        tester.widget<LinearProgressIndicator>(progress).value,
        closeTo(25 / 80, .001),
      );

      await tester.tap(find.text('GOING ✓'));
      await tester.pump();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(harness.app.hasConfirmedRsvp(repository.gig.id), isFalse);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("WHO'S GOING"), findsNothing);

      repository.completeMutation();
      await tester.pumpAndSettle();
      expect(harness.app.rsvpCount(repository.gig), 24);
      expect(find.textContaining('GOING'), findsNothing);
      expect(find.text("WHO'S GOING"), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('failed RSVP rolls back the count and keeps attendance gated', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _AttendanceRepository(
      auth: auth,
      gig: _textOnlyGig(going: 7, cap: 'No cap'),
    )..failNextMutation = true;
    addTearDown(repository.close);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
      beforePump: (app) => app.openGig('shared-gig'),
    );

    await tester.tap(find.text('RSVP'));
    await tester.pump();
    expect(harness.app.rsvpCount(repository.gig), 8);

    repository.completeMutation();
    await tester.pumpAndSettle();
    expect(harness.app.rsvps, isNot(contains('shared-gig')));
    expect(harness.app.rsvpCount(repository.gig), 7);
    expect(find.text("WHO'S GOING"), findsNothing);
    expect(harness.app.toast, 'Something broke. Try again.');
  });

  testWidgets('confirmed no-cap RSVP shows a count without a percentage', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _AttendanceRepository(
      auth: auth,
      gig: _textOnlyGig(going: 4, cap: 'No cap'),
      initiallyRsvpd: true,
    );
    addTearDown(repository.close);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'shared-gig')),
      beforePump: (app) => app.openGig('shared-gig'),
    );

    expect(find.text("WHO'S GOING"), findsOne);
    expect(find.text('4+ GOING'), findsOne);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    repository.emitGig(
      repository.gig.copyWith(lifecycle: GigLifecycle.cancelled),
    );
    await tester.pumpAndSettle();
    expect(find.text("WHO'S GOING"), findsNothing);
  });

  testWidgets('paid gigs show the buy tickets CTA with their price', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g8')),
    );

    expect(find.text(r'BUY TICKETS · $25.00'), findsOne);
    expect(find.byKey(const Key('gig-buy-tickets')), findsOne);
    expect(
      find.text(
        'TICKETS ARE SOLD BY THE ORGANIZER · EARPLUG FEE ADDED AT CHECKOUT',
      ),
      findsOne,
    );
    expect(find.text('RSVP'), findsNothing);
    expect(find.textContaining('AT DOOR'), findsNothing);
    final meta = find.byKey(const Key('gig-fact-meta'));
    final price = find.descendant(of: meta, matching: find.text(r'$25.00'));
    expect(
      tester.widget<Text>(price).style?.color,
      tester.element(meta).epColors.ink,
    );
    expect(
      find.descendant(of: meta, matching: find.textContaining('GOING')),
      findsNothing,
    );
  });

  testWidgets('buy tickets opens the purchase sheet for signed-in fans', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g8')),
    );

    await tester.tap(find.byKey(const Key('gig-buy-tickets')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ticket-hold')), findsOne);
    expect(find.text('HOLD TICKETS'), findsOne);
  });

  testWidgets('buy tickets gates signed-out fans through sign-in', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g8')),
    );

    await tester.tap(find.byKey(const Key('gig-buy-tickets')));
    await tester.pumpAndSettle();

    expect(harness.app.pending?.kind, PendingKind.tickets);
    expect(harness.app.pending?.id, 'g8');
    expect(find.byKey(const Key('ticket-hold')), findsNothing);
  });

  testWidgets(
    'gig detail blurs known people and reveals their relation subtitles in a sheet',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final harness = await pumpApp(
        tester,
        auth: auth,
        home: const Scaffold(body: GigDetailScreen(gigId: 'g9')),
      );

      harness.app.toggleRsvp('g9');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      final people = find.byKey(const ValueKey('gig-people-you-know'));
      expect(people, findsOneWidget);
      expect(find.text('PEOPLE YOU MAY KNOW · 2'), findsOneWidget);
      expect(find.text('2 people you may know are going'), findsOneWidget);
      for (final id in ['u-maya', 'u-theo']) {
        final blur = find.byKey(ValueKey('gig-people-blur-$id'));
        expect(blur, findsOneWidget);
        expect(
          tester.widget<ImageFiltered>(blur).imageFilter,
          ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        );
        expect(find.byKey(ValueKey('known-person-$id')), findsNothing);
      }
      expect(find.text('25+ GOING'), findsOneWidget);
      expect(find.byKey(const ValueKey('gig-people-sheet')), findsNothing);

      await tester.ensureVisible(people);
      await tester.pumpAndSettle();
      await tester.tap(people);
      await tester.pumpAndSettle();

      final sheet = find.byKey(const ValueKey('gig-people-sheet'));
      expect(sheet, findsOneWidget);
      for (final id in ['u-maya', 'u-theo']) {
        expect(
          find.descendant(
            of: sheet,
            matching: find.byKey(ValueKey('known-person-$id')),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: sheet, matching: find.text('Friend')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Seen at 2 shows')),
        findsOneWidget,
      );
    },
  );

  testWidgets('gig detail shows nothing extra when signed out', (tester) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g9')),
    );

    expect(find.byKey(const ValueKey('gig-people-you-know')), findsNothing);
  });

  testWidgets('gig detail shows nothing extra when no known people are going', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g1')),
    );

    harness.app.toggleRsvp('g1');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gig-people-you-know')), findsNothing);
    expect(find.text("WHO'S GOING"), findsOneWidget);
    expect(find.text('44+ GOING'), findsOneWidget);
  });

  testWidgets('loadKnownAttendees is requested once per open', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _KnownAttendeesCountingRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g9')),
    );

    expect(repository.knownAttendeesCalls, 1);
    harness.app.notifyListeners();
    await tester.pump();
    harness.app.toggleRsvp('g9');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repository.knownAttendeesCalls, 1);
  });
}

List<Uri> _recordExternalLaunches(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <Uri>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    if (call.method != 'launch') return null;
    final arguments = call.arguments as Map<Object?, Object?>;
    launches.add(Uri.parse(arguments['url']! as String));
    return true;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return launches;
}

Future<AppHarness> _pumpPresentation(
  WidgetTester tester,
  Gig gig, {
  Uint8List? flyerBytes,
  String? previewLabel,
  bool venueSet = true,
  Size size = const Size(402, 900),
}) => pumpApp(
  tester,
  size: size,
  home: Scaffold(
    body: Builder(
      builder: (context) => GigDetailPresentation(
        gig: gig,
        app: context.watch<AppState>(),
        performers: gig.performers,
        flyerBytes: flyerBytes,
        previewLabel: previewLabel,
        venueSet: venueSet,
      ),
    ),
  ),
);

Gig _textOnlyGig({
  GigLifecycle lifecycle = GigLifecycle.published,
  String desc = 'A direct-link show.',
  int going = 0,
  String cap = 'No cap',
}) {
  final startsAt = DateTime.now().add(const Duration(days: 2));
  return gigFixture(
    id: 'shared-gig',
    title: 'Shared Show',
    startsAt: startsAt,
    doorsAt: startsAt.subtract(const Duration(hours: 1)),
    flyKey: 'xerox',
    performers: const [
      GigPerformer(
        id: '',
        kind: GigPerformerKind.text,
        name: 'Text Only Opener',
        role: GigPerformerRole.opener,
      ),
    ],
    going: going,
    desc: desc,
    cap: cap,
    lifecycle: lifecycle,
  );
}

class _ControlledPublicGigRepository extends DemoRepository {
  _ControlledPublicGigRepository({required super.auth});

  final _controller = StreamController<Gig?>.broadcast();
  Gig? _current;

  @override
  Stream<Gig?> publicGig(String gigId) {
    Future<void>.microtask(() => _controller.add(_current));
    return _controller.stream;
  }

  void emit(Gig gig) {
    _current = gig;
    _controller.add(gig);
  }
}

class _AttendanceRepository extends DemoRepository {
  _AttendanceRepository({
    required super.auth,
    required this.gig,
    bool initiallyRsvpd = false,
  }) {
    if (initiallyRsvpd) _rsvpIds.add(gig.id);
  }

  Gig gig;
  bool failNextMutation = false;
  final Set<String> _rsvpIds = {};
  final StreamController<Interactions> _interactions =
      StreamController<Interactions>.broadcast();
  final StreamController<Gig?> _publicGig = StreamController<Gig?>.broadcast();
  Completer<void>? _mutation;

  Interactions get _snapshot => Interactions(
    rsvpGigIds: Set.unmodifiable(_rsvpIds),
    followBandIds: const {},
    savedGigIds: const {},
    gigs: _rsvpIds.contains(gig.id) ? [gig] : const [],
    attendedCount: 0,
  );

  @override
  Stream<Interactions> myInteractions() async* {
    yield _snapshot;
    yield* _interactions.stream;
  }

  @override
  Stream<Gig?> publicGig(String ref) async* {
    yield gig;
    yield* _publicGig.stream;
  }

  @override
  Future<void> toggleRsvp(String gigId, {bool? on}) async {
    final mutation = Completer<void>();
    _mutation = mutation;
    await mutation.future;
    _mutation = null;
    if (failNextMutation) {
      failNextMutation = false;
      throw StateError('RSVP update failed');
    }

    final wasGoing = _rsvpIds.contains(gigId);
    final goingNow = on ?? !wasGoing;
    if (goingNow == wasGoing) return;
    goingNow ? _rsvpIds.add(gigId) : _rsvpIds.remove(gigId);
    gig = gig.copyWith(going: gig.going + (goingNow ? 1 : -1));
    _interactions.add(_snapshot);
    _publicGig.add(gig);
  }

  void completeMutation() {
    final mutation = _mutation;
    if (mutation == null) throw StateError('No RSVP mutation is pending.');
    mutation.complete();
  }

  void emitGoing(int count) => emitGig(gig.copyWith(going: count));

  void emitGig(Gig value) {
    gig = value;
    _interactions.add(_snapshot);
    _publicGig.add(gig);
  }

  Future<void> close() async {
    await _interactions.close();
    await _publicGig.close();
  }
}

class _KnownAttendeesCountingRepository extends DemoRepository {
  _KnownAttendeesCountingRepository({required super.auth});

  int knownAttendeesCalls = 0;

  @override
  Future<KnownAttendees> knownAttendees(
    String gigId, {
    required DateTime now,
  }) async {
    knownAttendeesCalls++;
    return super.knownAttendees(gigId, now: now);
  }
}
