import 'package:flutter_test/flutter_test.dart';

import 'package:videoapp/core_bridge.dart';
import 'package:videoapp/models.dart';
import 'package:videoapp/playback_loader.dart';

class _StubRepository extends AppRepository {
  Future<PlaybackPlan> Function(Drama, Episode, {int? quality})? onResolve;
  int resolveCalls = 0;
  int cancelPlaybackCalls = 0;
  int releaseCalls = 0;

  @override
  Future<CatalogPage> catalog(String source, {int page = 1, String query = '', String category = '', bool force = false}) async => throw UnimplementedError();

  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async => throw UnimplementedError();

  @override
  Future<String> cover(Drama drama, {bool force = false}) async => throw UnimplementedError();

  @override
  Future<DramaDetail> detail(Drama drama) async => throw UnimplementedError();

  @override
  Future<void> initialize() async {}

  @override
  Future<PlaybackPlan> resolve(Drama drama, Episode episode, {int quality = 0}) async {
    resolveCalls++;
    if (onResolve != null) {
      return onResolve!(drama, episode, quality: quality);
    }
    return const PlaybackPlan(url: 'https://example.com/video.mp4', session: 's1');
  }

  @override
  Future<PlaybackPlan> fallback(PlaybackPlan current) async => current;

  @override
  Future<void> cancelPlayback() async {
    cancelPlaybackCalls++;
  }

  @override
  Future<void> release(String session) async {
    releaseCalls++;
  }
}

Drama testDrama() => const Drama(
      id: 'hongguo:1',
      source: 'hongguo',
      title: 'Test Drama',
      category: '',
      episodes: 10,
    );

Episode testEpisode() => Episode({}, 1);

void main() {
  group('PlaybackLoader', () {
    test('load success returns plan', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      final plan = await loader.load(testDrama(), testEpisode());

      expect(plan, isNotNull);
      expect(plan?.url, 'https://example.com/video.mp4');
      expect(repo.resolveCalls, 1);
      expect(repo.cancelPlaybackCalls, 1);
    });

    test('load with localOnly uses localPlayback', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      // localPlayback 默認返回 null，應該拋出 AppFailure
      expect(
        () async => await loader.load(testDrama(), testEpisode(), localOnly: true),
        throwsA(isA<AppFailure>()),
      );
    });

    test('load with online uses resolveOnline', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      final plan = await loader.load(testDrama(), testEpisode(), online: true);

      expect(plan, isNotNull);
      expect(repo.resolveCalls, 1);
    });

    test('fallback calls repository.fallback', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);
      final current = const PlaybackPlan(url: 'https://example.com/video.mp4', session: 's1');

      await loader.fallback(current);

      expect(repo.cancelPlaybackCalls, 1);
    });

    test('use returns prepared plan', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);
      final prepared = const PlaybackPlan(url: 'https://example.com/video.mp4', session: 's1');

      final plan = await loader.use(prepared);

      expect(plan?.url, 'https://example.com/video.mp4');
    });

    test('close prevents further loads', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      await loader.close();

      final plan = await loader.load(testDrama(), testEpisode());
      expect(plan, isNull);
    });

    test('load after close returns null without calling resolve', () async {
      final repo = _StubRepository();
      final loader = PlaybackLoader(repo);

      await loader.close();

      await loader.load(testDrama(), testEpisode());
      expect(repo.resolveCalls, 0);
    });

    test('resolve failure propagates error', () async {
      final repo = _StubRepository()
        ..onResolve = (_, __, {int? quality}) => Future.error(AppFailure('播放地址获取失败'));
      final loader = PlaybackLoader(repo);

      expect(
        () async => await loader.load(testDrama(), testEpisode()),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
