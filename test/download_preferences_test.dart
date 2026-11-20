import 'package:flutter_test/flutter_test.dart';

import 'package:videoapp/download_preferences.dart';

void main() {
  group('DownloadPreferences', () {
    test('default values', () {
      final prefs = DownloadPreferences();
      expect(prefs.quality, 0);
      expect(prefs.includeVip, false);
      expect(prefs.qualityLabel, '自动 · 优先高清');
    });

    test('qualityLabel for explicit quality', () {
      final prefs = DownloadPreferences(quality: 1080, includeVip: true);
      expect(prefs.qualityLabel, '1080P');
    });

    test('qualities list contains expected values', () {
      expect(DownloadPreferences.qualities, [0, 1080, 720, 480]);
    });

    test('copyWith updates fields', () {
      final prefs = DownloadPreferences(quality: 720, includeVip: false);
      final copied = prefs.copyWith(quality: 1080);
      expect(copied.quality, 1080);
      expect(copied.includeVip, false);
      expect(copied.qualityLabel, '1080P');
    });

    test('copyWith includeVip', () {
      final prefs = DownloadPreferences(quality: 0, includeVip: false);
      final copied = prefs.copyWith(includeVip: true);
      expect(copied.quality, 0);
      expect(copied.includeVip, true);
    });

    test('toJson and fromJson round trip', () {
      final prefs = DownloadPreferences(quality: 480, includeVip: true);
      final json = prefs.toJson();
      expect(json['quality'], 480);
      expect(json['includeVip'], true);

      final restored = DownloadPreferences.fromJson(json);
      expect(restored.quality, 480);
      expect(restored.includeVip, true);
    });

    test('fromJson default values', () {
      final restored = DownloadPreferences.fromJson({});
      expect(restored.quality, 0);
      expect(restored.includeVip, false);
    });

    test('fromJson invalid quality throws', () {
      expect(
        () => DownloadPreferences.fromJson({'quality': 999, 'includeVip': false}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson invalid includeVip type throws', () {
      expect(
        () => DownloadPreferences.fromJson({'quality': 0, 'includeVip': 'yes'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJson non-int quality throws', () {
      expect(
        () => DownloadPreferences.fromJson({'quality': '720', 'includeVip': false}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
