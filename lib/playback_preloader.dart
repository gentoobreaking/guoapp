import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core_bridge.dart';
import 'models.dart';

class _Prepared {
  const _Prepared(this.episode, this.plan, this.expires);
  final Episode episode;
  final PlaybackPlan plan;
  final DateTime expires;
}

class PlaybackPreloader extends ChangeNotifier {
  PlaybackPreloader(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppRepository repository;
  final DateTime Function() _now;
  final List<Episode> _queue = [];
  final List<_Prepared> _prepared = [];
  String? _base;
  Drama? _drama;
  int _quality = 0;
  bool _online = false;
  Timer? _delay;
  DateTime _retryAt = DateTime(2000);
  int _generation = 0;
  bool _closed = false, loading = false;
  String error = '';

  void _release(PlaybackPlan plan) =>
      unawaited(repository.release(plan.session).catchError((Object _) {}));

  String _baseKey(Drama drama, int quality, bool online) =>
      '${drama.id}\u0000$quality\u0000$online';

  bool _fresh(_Prepared entry) => _now().isBefore(entry.expires);

  /// 已按观看顺序准备就绪的集数。
  int get count => _prepared.length;

  bool get ready => _prepared.isNotEmpty && _fresh(_prepared.first);

  String get status {
    if (_prepared.isNotEmpty) {
      final fresh = _prepared.where(_fresh).toList();
      if (fresh.isNotEmpty) {
        final bytes = fresh.fold<int>(
          0,
          (sum, entry) => sum + entry.plan.prefetchedBytes,
        );
        if (fresh.first.plan.local) {
          return fresh.length > 1 ? '已预载 ${fresh.length} 集 · 本地已下载' : '下一集已下载';
        }
        return bytes > 0
            ? '已预载 ${fresh.length} 集 · 预取 ${(bytes / 1024).ceil()} KB'
            : '已预载 ${fresh.length} 集 · 播放地址已准备';
      }
    }
    if (loading || _delay != null) return '正在准备下一集';
    return error.isNotEmpty ? '下一集预加载暂不可用，切集时会重新获取' : '播放后段提前准备后面的剧集';
  }

  void prepare(
    Drama drama,
    List<Episode> upcoming, {
    int quality = 0,
    bool online = false,
  }) {
    if (_closed || upcoming.isEmpty) return;
    final base = _baseKey(drama, quality, online);
    if (_base != base) {
      _generation++;
      _releaseAll();
      _queue.clear();
      _base = base;
      _drama = drama;
      _quality = quality;
      _online = online;
      error = '';
      _retryAt = DateTime(2000);
    }
    final wanted = {for (final episode in upcoming) episode.number};
    for (final entry in [..._prepared]) {
      if (_fresh(entry) && wanted.contains(entry.episode.number)) continue;
      _prepared.remove(entry);
      _release(entry.plan);
      if (wanted.contains(entry.episode.number) &&
          !_queue.any((e) => e.number == entry.episode.number)) {
        _queue.add(entry.episode);
      }
    }
    _queue.removeWhere((episode) => !wanted.contains(episode.number));
    final have = {
      for (final entry in _prepared) entry.episode.number,
      for (final episode in _queue) episode.number,
    };
    for (final episode in upcoming) {
      if (!have.contains(episode.number)) _queue.add(episode);
    }
    _pump();
    if (!_closed) notifyListeners();
  }

  void _pump() {
    if (_closed || loading || _delay != null || _queue.isEmpty) return;
    if (_now().isBefore(_retryAt)) return;
    final ticket = _generation;
    _delay = Timer(const Duration(milliseconds: 600), () => _work(ticket));
  }

  Future<void> _work(int ticket) async {
    _delay = null;
    while (!_closed && ticket == _generation && _queue.isNotEmpty) {
      final episode = _queue.removeAt(0);
      if (_prepared.any((entry) => entry.episode.number == episode.number)) {
        continue;
      }
      final drama = _drama;
      if (drama == null) return;
      loading = true;
      notifyListeners();
      try {
        final plan = await repository.preload(
          drama,
          episode,
          quality: _quality,
          online: _online,
        );
        if (_closed || ticket != _generation) {
          if (plan != null) await repository.release(plan.session);
          return;
        }
        if (plan == null || plan.url.isEmpty) throw AppFailure('未取得预加载结果');
        // 站源返回凭证有效期时尽量用满（上限 10 分钟），避免一集还没看完
        // 预载计划就作废、切集时又要重新走一遍慢速解析；未返回时保守保留 2 分钟。
        final reported = plan.expiresAt > 0
            ? DateTime.fromMillisecondsSinceEpoch(
                plan.expiresAt,
              ).subtract(const Duration(seconds: 5))
            : null;
        final cap = _now().add(const Duration(minutes: 10));
        final expires = reported == null
            ? _now().add(const Duration(minutes: 2))
            : reported.isBefore(cap)
            ? reported
            : cap;
        if (!expires.isAfter(_now())) {
          _release(plan);
          throw AppFailure('下一集播放凭证即将过期');
        }
        _prepared.add(_Prepared(episode, plan, expires));
        error = '';
      } catch (failure) {
        if (_closed || ticket != _generation) return;
        error = failure.toString();
        _retryAt = _now().add(const Duration(seconds: 30));
        return;
      } finally {
        loading = false;
        if (!_closed) notifyListeners();
      }
    }
    if (!_closed && ticket == _generation && _queue.isNotEmpty) {
      _delay = Timer(const Duration(milliseconds: 600), () => _pump());
    }
  }

  PlaybackPlan? take(
    Drama drama,
    Episode episode, {
    int quality = 0,
    bool online = false,
  }) {
    if (_base != _baseKey(drama, quality, online)) return null;
    final index = _prepared.indexWhere(
      (entry) => entry.episode.number == episode.number,
    );
    if (index < 0) return null;
    final entry = _prepared.removeAt(index);
    if (!_fresh(entry)) {
      _release(entry.plan);
      if (!_queue.any((e) => e.number == episode.number)) {
        _queue.insert(0, episode);
      }
      _pump();
      return null;
    }
    if (!_closed) notifyListeners();
    return entry.plan;
  }

  /// 切集后丢弃已观看（含回跳跳过）集数的计划，保留仍在观看顺序之后的计划。
  void advance(
    Drama drama,
    int number, {
    int quality = 0,
    bool online = false,
  }) {
    if (_closed) return;
    if (_base != _baseKey(drama, quality, online)) {
      clear();
      return;
    }
    final before = _prepared.length + _queue.length;
    for (final entry in [..._prepared]) {
      if (entry.episode.number > number) continue;
      _prepared.remove(entry);
      _release(entry.plan);
    }
    _queue.removeWhere((episode) => episode.number <= number);
    if (_prepared.length + _queue.length != before && !_closed) {
      notifyListeners();
    }
  }

  void pause() {
    final changed = loading || _delay != null;
    _generation++;
    _delay?.cancel();
    _delay = null;
    if (loading) {
      unawaited(repository.cancelPreload().catchError((Object _) {}));
    }
    loading = false;
    if (changed && !_closed) notifyListeners();
  }

  void _releaseAll() {
    for (final entry in _prepared) {
      _release(entry.plan);
    }
    _prepared.clear();
  }

  void clear() {
    pause();
    _releaseAll();
    _queue.clear();
    _base = null;
    _drama = null;
    _retryAt = DateTime(2000);
    error = '';
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    clear();
    super.dispose();
  }
}
