import 'dart:async';

import 'core_bridge.dart';

/// 區網內發現的裝置資訊。
class LanDevice {
  const LanDevice({
    required this.id,
    required this.name,
    required this.version,
    required this.host,
    required this.port,
  });
  final String id;
  final String name;
  final String version;
  final String host;
  final int port;

  factory LanDevice.fromJson(Map<String, dynamic> json) => LanDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        version: json['version'] as String? ?? '',
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 0,
      );

  String get address => '$host:$port';
}

/// LAN 裝置同步服務。
class LanSyncService {
  LanSyncService(this.repository);
  final NativeRepository repository;

  bool _started = false;

  /// 啟動本地 LAN 同步伺服器（HTTP + UDP 探索）。
  Future<void> start() async {
    if (_started) return;
    await repository.lanStart();
    _started = true;
  }

  /// 停止 LAN 同步伺服器。
  Future<void> stop() async {
    if (!_started) return;
    await repository.lanStop();
    _started = false;
  }

  /// 掃描區網內的其他裝置。
  Future<List<LanDevice>> scan() async {
    await start();
    final result = await repository.lanScan();
    final devices = <LanDevice>[];
    for (final row in (result['devices'] as List? ?? const [])) {
      if (row is Map) {
        devices.add(LanDevice.fromJson(Map<String, dynamic>.from(row)));
      }
    }
    return devices;
  }

  /// 獲取本機裝置資訊。
  Future<Map<String, dynamic>> info() async {
    await start();
    return repository.lanInfo();
  }

  /// 從指定裝置同步資料（觀看紀錄、最愛、追劇）。
  Future<void> syncFrom(String deviceId) async {
    await start();
    await repository.lanSync(deviceId);
    _started = false;
    await stop();
  }
}
