import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:videoapp/local_snapshot.dart';

void main() {
  group('LocalSnapshot legacy', () {
    test('storageKey is legacy', () {
      expect(LocalSnapshot.legacy(LocalSnapshot.storageKey), isTrue);
    });

    test('owns key is legacy', () {
      expect(LocalSnapshot.legacy('profiles'), isTrue);
    });

    test('seriesCandidates prefix is legacy', () {
      expect(LocalSnapshot.legacy('seriesCandidates.foo'), isTrue);
    });

    test('followChecks prefix is legacy', () {
      expect(LocalSnapshot.legacy('followChecks.bar'), isTrue);
    });

    test('unknown key is not legacy', () {
      expect(LocalSnapshot.legacy('unknown.key'), isFalse);
    });
  });

  group('LocalSnapshot owns', () {
    test('global keys are owned', () {
      for (final key in LocalSnapshot.globalKeys) {
        expect(LocalSnapshot.owns(key), isTrue, reason: '$key should be owned');
      }
    });

    test('library keys are owned', () {
      for (final key in LocalSnapshot.libraryKeys) {
        expect(LocalSnapshot.owns(key), isTrue, reason: '$key should be owned');
      }
    });

    test('profile prefixed keys are owned', () {
      expect(
        LocalSnapshot.owns('profile.default.history'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.favorites'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.followStates'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.seriesCandidates'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.mediaHistory'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.source'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.hideVip'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.playback'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.downloadPreferences'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.catalogView'),
        isTrue,
      );
      expect(
        LocalSnapshot.owns('profile.default.recentSearches'),
        isTrue,
      );
    });

    test('unknown key is not owned', () {
      expect(LocalSnapshot.owns('unknown.key'), isFalse);
    });

    test('profile with invalid id chars is not owned', () {
      expect(LocalSnapshot.owns('profile.invalid id!.history'), isFalse);
    });
  });

  group('LocalSnapshot _validate via reloadValues', () {
    SharedPreferences? prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('empty snapshot loads empty values', () async {
      final snapshot = LocalSnapshot(prefs!);
      expect(snapshot.values, isEmpty);
    });

    test('valid snapshot loads values', () async {
      await prefs!.setString('profiles', '[]');
      await prefs!.setBool('hideVip', true);
      final snapshot = LocalSnapshot(prefs!);
      expect(snapshot.getString('profiles'), '[]');
      expect(snapshot.getBool('hideVip'), true);
    });

    test('invalid snapshot throws FormatException', () async {
      await prefs!.setString(LocalSnapshot.storageKey, 'invalid');
      expect(
        () => LocalSnapshot(prefs!),
        throwsA(isA<FormatException>()),
      );
    });

    test('snapshot with wrong version throws FormatException', () async {
      await prefs!.setString(
        LocalSnapshot.storageKey,
        '{"version": 2, "values": {}}',
      );
      expect(
        () => LocalSnapshot(prefs!),
        throwsA(isA<FormatException>()),
      );
    });

    test('snapshot without profiles throws FormatException', () async {
      await prefs!.setString(
        LocalSnapshot.storageKey,
        '{"version": 1, "values": {"hideVip": true}}',
      );
      expect(
        () => LocalSnapshot(prefs!),
        throwsA(isA<FormatException>()),
      );
    });

    test('retired keys are filtered out', () async {
      await prefs!.setString(
        LocalSnapshot.storageKey,
        '{"version": 1, "values": {"profiles": "[]", "sourceGateEnabled": true, "hideVip": false}}',
      );
      final snapshot = LocalSnapshot(prefs!);
      expect(snapshot.getString('sourceGateEnabled'), isNull);
      expect(snapshot.getBool('hideVip'), false);
    });

    test('lanRecords retired key is filtered out', () async {
      await prefs!.setString(
        LocalSnapshot.storageKey,
        '{"version": 1, "values": {"profiles": "[]", "lanRecords": [], "hideVip": false}}',
      );
      final snapshot = LocalSnapshot(prefs!);
      expect(snapshot.getString('lanRecords'), isNull);
      expect(snapshot.getBool('hideVip'), false);
    });

    test('profile lanRecords retired key is filtered out', () async {
      await prefs!.setString(
        LocalSnapshot.storageKey,
        '{"version": 1, "values": {"profiles": "[]", "profile.default.lanRecords": [], "hideVip": false}}',
      );
      final snapshot = LocalSnapshot(prefs!);
      expect(snapshot.getString('profile.default.lanRecords'), isNull);
      expect(snapshot.getBool('hideVip'), false);
    });
  });
}
