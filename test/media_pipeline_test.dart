import 'package:flutter_test/flutter_test.dart';

import 'package:videoapp/core_bridge.dart';
import 'package:videoapp/media_pipeline.dart';

void main() {
  group('MediaProbe', () {
    test('streams 返回所有串流', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
          {'codec_type': 'audio', 'codec_name': 'aac'},
          {'codec_type': 'subtitle', 'codec_name': 'mov_text'},
        ],
      });
      expect(probe.streams.length, 3);
    });

    test('streams 為空時返回空列表', () {
      final probe = MediaProbe({});
      expect(probe.streams, isEmpty);
    });

    test('video 返回視訊串流', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'audio', 'codec_name': 'aac'},
          {'codec_type': 'video', 'codec_name': 'h264'},
        ],
      });
      expect(probe.video['codec_name'], 'h264');
    });

    test('video 無視訊串流時返回空 Map', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
      });
      expect(probe.video, isEmpty);
    });

    test('duration 從 format.duration 解析', () {
      final probe = MediaProbe({
        'format': {'duration': '120.5'},
      });
      expect(probe.duration, 120.5);
    });

    test('duration 無效時返回 0', () {
      final probe = MediaProbe({
        'format': {'duration': 'invalid'},
      });
      expect(probe.duration, 0);
    });

    test('duration 無 format 時返回 0', () {
      final probe = MediaProbe({});
      expect(probe.duration, 0);
    });

    test('videoCodec 返回視訊編解碼', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'hevc'},
        ],
      });
      expect(probe.videoCodec, 'hevc');
    });

    test('audioCodec 返回音訊編解碼', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'audio', 'codec_name': 'opus'},
        ],
      });
      expect(probe.audioCodec, 'opus');
    });

    test('audioCodec 無音訊串流時返回空字串', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
        ],
      });
      expect(probe.audioCodec, '');
    });
  });

  group('verifyMediaDuration', () {
    test('正常影片通過驗證', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
        'format': {'duration': '100'},
      });
      expect(() => verifyMediaDuration(probe, 100), returnsNormally);
    });

    test('時長誤差在 2 秒內通過驗證', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
        'format': {'duration': '100'},
      });
      expect(() => verifyMediaDuration(probe, 99), returnsNormally);
    });

    test('時長誤差超過 2% 時拋出 AppFailure', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
        'format': {'duration': '100'},
      });
      expect(() => verifyMediaDuration(probe, 95), throwsA(isA<AppFailure>()));
    });

    test('無視訊無音訊時拋出 AppFailure', () {
      final probe = MediaProbe({
        'streams': [],
        'format': {'duration': '100'},
      });
      expect(() => verifyMediaDuration(probe, 100), throwsA(isA<AppFailure>()));
    });

    test('時長為 0 時拋出 AppFailure', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
        'format': {'duration': '0'},
      });
      expect(() => verifyMediaDuration(probe, 100), throwsA(isA<AppFailure>()));
    });

    test('時長為負數時拋出 AppFailure', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
        'format': {'duration': '-1'},
      });
      expect(() => verifyMediaDuration(probe, 100), throwsA(isA<AppFailure>()));
    });

    test('expected 為 0 時不檢查誤差', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
          {'codec_type': 'audio', 'codec_name': 'aac'},
        ],
        'format': {'duration': '50'},
      });
      expect(() => verifyMediaDuration(probe, 0), returnsNormally);
    });

    test('NaN 時長拋出 AppFailure', () {
      final probe = MediaProbe({
        'streams': [
          {'codec_type': 'video', 'codec_name': 'h264'},
        ],
        'format': {'duration': 'nan'},
      });
      expect(() => verifyMediaDuration(probe, 100), throwsA(isA<AppFailure>()));
    });
  });
}
