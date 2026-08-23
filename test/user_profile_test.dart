import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile fan onboarding', () {
    test('parses enrolled fan state', () {
      final profile = UserProfile.fromJson({
        'name': 'Sam Reyes',
        'email': 'sam@example.com',
        'genres': <String>['punk'],
        'attendedCount': 2,
        'createdAt': 1234,
        'fanOnboarding': <String, Object?>{
          'preferredCity': 'oak',
          'genreChoice': 'selected',
          'collapsed': true,
        },
      });

      expect(profile.fanOnboarding?.preferredCity, FanCity.oak);
      expect(profile.fanOnboarding?.genreChoice, FanGenreChoice.selected);
      expect(profile.fanOnboarding?.collapsed, isTrue);
    });

    test('keeps legacy or unenrolled profiles unenrolled', () {
      Map<String, Object?> legacyProfile({Object? fanOnboarding}) => {
        'name': 'Legacy Fan',
        'email': 'legacy@example.com',
        'genres': <String>[],
        'attendedCount': 0,
        'createdAt': 1234,
        'fanOnboarding': ?fanOnboarding,
      };

      expect(UserProfile.fromJson(legacyProfile()).fanOnboarding, isNull);
      expect(
        UserProfile.fromJson({
          ...legacyProfile(),
          'fanOnboarding': null,
        }).fanOnboarding,
        isNull,
      );
    });
  });
}
