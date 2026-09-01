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

    test('uses privacy-safe defaults for existing user payloads', () {
      final profile = UserProfile.fromJson({
        'name': 'Legacy Fan',
        'email': 'legacy@example.com',
        'genres': <String>[],
        'attendedCount': 0,
        'createdAt': 1234,
      });

      expect(profile.avatarUrl, isNull);
      expect(profile.bio, isNull);
      expect(profile.homeLocation, isNull);
      expect(profile.locationPersonalizationEnabled, isFalse);
      expect(profile.followedBandUpdatesEnabled, isTrue);
      expect(profile.profileTutorialAvailable, isFalse);
      expect(profile.profileTutorialCompleted, isFalse);
    });

    test('parses editable identity and preference fields', () {
      final profile = UserProfile.fromJson({
        'name': 'Sam Reyes',
        'email': 'sam@example.com',
        'genres': <String>['punk', 'noise'],
        'attendedCount': 2,
        'createdAt': 1234,
        'avatarUrl': 'https://example.com/avatar.jpg',
        'bio': 'Always by the speakers.',
        'homeLocation': 'berkeley',
        'locationPersonalizationEnabled': true,
        'followedBandUpdatesEnabled': false,
        'profileTutorialCompleted': true,
      });

      expect(profile.avatarUrl, 'https://example.com/avatar.jpg');
      expect(profile.bio, 'Always by the speakers.');
      expect(profile.homeLocation, FanCity.berkeley);
      expect(profile.locationPersonalizationEnabled, isTrue);
      expect(profile.followedBandUpdatesEnabled, isFalse);
      expect(profile.profileTutorialAvailable, isTrue);
      expect(profile.profileTutorialCompleted, isTrue);
    });
  });

  group('fan home location search', () {
    test('matches city names and common region formats case-insensitively', () {
      expect(fanCityFromLocationInput('berkeley'), FanCity.berkeley);
      expect(fanCityFromLocationInput('BERKELEY, CA'), FanCity.berkeley);
      expect(
        fanCityFromLocationInput('San Mateo, California'),
        FanCity.sanMateo,
      );
      expect(fanCityFromLocationInput('sf'), FanCity.sf);
      expect(fanCityFromLocationInput('unknown'), isNull);
    });

    test('suggests only supported locations', () {
      expect(fanCitySuggestions('san').toList(), [
        FanCity.sf,
        FanCity.sanMateo,
        FanCity.sanJose,
        FanCity.sanRafael,
      ]);
      expect(fanCitySuggestions('los angeles'), isEmpty);
    });
  });

  test('fan history parses the enriched RSVP-only wire shape', () {
    final item = FanHistoryItem.fromJson({
      'gigId': 'gig-1',
      'title': 'Noise Night',
      'startsAt': 1774137600000,
      'venueName': 'Peralta Hall',
      'bandNames': <String>['Static Bloom', 'Court Date'],
      'flyKey': 'blue',
      'flyerUrl': null,
      'status': 'rsvped',
    });

    expect(item.gigId, 'gig-1');
    expect(item.venueName, 'Peralta Hall');
    expect(item.bandNames, ['Static Bloom', 'Court Date']);
    expect(item.flyerUrl, isNull);
    expect(item.status, FanHistoryStatus.rsvped);
  });
}
