import 'package:earplug/demo_data.dart';
import 'package:earplug/services/flyer_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = FlyerEntryParser();

  test('proposes structured gig fields from recognized flyer text', () {
    final proposal = parser.parse(
      const FlyerTextExtraction([
        'NIGHT OF NOISE',
        'Foghorn Diet',
        'Pigeon Court',
        'August 29, 2026',
        'The Foghorn Club',
        'Doors 7:30 PM / Show 8:30 PM',
        '\$12',
      ]),
      venues: DemoData.venues.values.toList(),
      bands: DemoData.bands.values.toList(),
      now: DateTime(2026, 8, 24),
    );

    expect(proposal.title, 'NIGHT OF NOISE');
    expect(proposal.date, DateTime(2026, 8, 29));
    expect((proposal.doors?.hour, proposal.doors?.minute), (19, 30));
    expect((proposal.start?.hour, proposal.start?.minute), (20, 30));
    expect(proposal.venueId, 'v1');
    expect(proposal.price, 12);
    expect(
      proposal.bands.map((band) => band.id),
      containsAll(<String>['b1', 'b2']),
    );
  });

  test('understands free admission and rolls a past month into next year', () {
    final proposal = parser.parse(
      const FlyerTextExtraction([
        'MATINEE BENEFIT',
        '1/12',
        'Doors 2PM',
        'Free admission',
      ]),
      venues: const [],
      bands: const [],
      now: DateTime(2026, 8, 24),
    );

    expect(proposal.date, DateTime(2027, 1, 12));
    expect((proposal.doors?.hour, proposal.doors?.minute), (14, 0));
    expect(proposal.price, 0);
  });
}
