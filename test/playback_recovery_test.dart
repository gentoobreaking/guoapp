import 'package:flutter_test/flutter_test.dart';

import 'package:videoapp/models.dart';
import 'package:videoapp/playback_recovery.dart';

PlaybackPlan planWithAlternative() => const PlaybackPlan(
      url: 'https://example.com/video.mp4',
      session: 'session-1',
      routeIndex: 0,
      routeCount: 2,
    );

PlaybackPlan planWithoutAlternative() => const PlaybackPlan(
      url: 'https://example.com/video.mp4',
      session: '',
      routeIndex: 0,
      routeCount: 1,
    );

void main() {
  group('PlaybackRecoveryAction', () {
    test('alternative when plan has alternative', () {
      final recovery = PlaybackRecovery();
      expect(recovery.next(planWithAlternative()), PlaybackRecoveryAction.alternative);
    });

    test('refresh once when no alternative', () {
      final recovery = PlaybackRecovery();
      expect(recovery.next(planWithoutAlternative()), PlaybackRecoveryAction.refresh);
    });

    test('stop after max attempts of alternative', () {
      final recovery = PlaybackRecovery();
      // maxAttempts = 3
      expect(recovery.next(planWithAlternative()), PlaybackRecoveryAction.alternative); // 1
      expect(recovery.next(planWithAlternative()), PlaybackRecoveryAction.alternative); // 2
      expect(recovery.next(planWithAlternative()), PlaybackRecoveryAction.alternative); // 3
      expect(recovery.next(planWithAlternative()), PlaybackRecoveryAction.stop); // >= maxAttempts
    });

    test('stop after refresh then no alternative', () {
      final recovery = PlaybackRecovery();
      expect(recovery.next(planWithoutAlternative()), PlaybackRecoveryAction.refresh); // refreshed=true
      expect(recovery.next(planWithoutAlternative()), PlaybackRecoveryAction.stop); // no alternative, already refreshed
    });

    test('reset allows retrying', () {
      final recovery = PlaybackRecovery();
      recovery.next(planWithAlternative());
      recovery.next(planWithAlternative());
      recovery.next(planWithAlternative());
      expect(recovery.next(planWithAlternative()), PlaybackRecoveryAction.stop);

      recovery.reset();
      expect(recovery.next(planWithAlternative()), PlaybackRecoveryAction.alternative);
    });

    test('alternative preferred over refresh', () {
      final recovery = PlaybackRecovery();
      // 先有一次 alternative，則 attempts=1
      recovery.next(planWithAlternative());
      // 再來一個沒有 alternative 的，應該 refresh
      expect(recovery.next(planWithoutAlternative()), PlaybackRecoveryAction.refresh);
    });
  });

  group('PlaybackHealth', () {
    test('not stalled when not playing', () {
      final health = PlaybackHealth();
      expect(
        health.stalled(
          position: const Duration(seconds: 10),
          playing: false,
          foreground: true,
          now: DateTime(2026, 1, 1, 12, 0, 0),
        ),
        isFalse,
      );
    });

    test('not stalled when not foreground', () {
      final health = PlaybackHealth();
      expect(
        health.stalled(
          position: const Duration(seconds: 10),
          playing: true,
          foreground: false,
          now: DateTime(2026, 1, 1, 12, 0, 0),
        ),
        isFalse,
      );
    });

    test('not stalled when position changed', () {
      final health = PlaybackHealth();
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
        health.stalled(
          position: const Duration(seconds: 10),
          playing: true,
          foreground: true,
          now: now,
        ),
        isFalse,
      );
      expect(
        health.stalled(
          position: const Duration(seconds: 20),
          playing: true,
          foreground: true,
          now: now.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
    });

    test('stalled after timeout with same position', () {
      final health = PlaybackHealth();
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      health.stalled(
        position: const Duration(seconds: 10),
        playing: true,
        foreground: true,
        now: now,
      );
      expect(
        health.stalled(
          position: const Duration(seconds: 10),
          playing: true,
          foreground: true,
          now: now.add(const Duration(seconds: 25)),
        ),
        isTrue,
      );
    });

    test('not stalled before timeout', () {
      final health = PlaybackHealth();
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      health.stalled(
        position: const Duration(seconds: 10),
        playing: true,
        foreground: true,
        now: now,
      );
      expect(
        health.stalled(
          position: const Duration(seconds: 10),
          playing: true,
          foreground: true,
          now: now.add(const Duration(seconds: 15)),
        ),
        isFalse,
      );
    });

    test('reset clears health state', () {
      final health = PlaybackHealth();
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      health.stalled(
        position: const Duration(seconds: 10),
        playing: true,
        foreground: true,
        now: now,
      );
      health.reset();
      expect(
        health.stalled(
          position: const Duration(seconds: 10),
          playing: true,
          foreground: true,
          now: now.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
    });
  });
}
