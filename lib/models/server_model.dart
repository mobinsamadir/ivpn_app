// lib/models/server_model.dart

import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

enum ServerType { ivpn, custom }

enum PingStatus { good, medium, bad, unknown }

@immutable
class Server {
  final String rawConfig;
  final String id;
  final String name;
  final String ip;
  final int port;
  final ServerType type;
  final int ping;
  final PingStatus status;
  final bool isConnected;
  final double downloadSpeed;
  final bool isTestingSpeed;
  final bool isFavorite;

  const Server({
    required this.rawConfig,
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.type,
    this.ping = -1,
    this.status = PingStatus.unknown,
    this.isConnected = false,
    this.downloadSpeed = 0.0,
    this.isTestingSpeed = false,
    this.isFavorite = false,
  });

  Server copyWith({
    String? name,
    int? ping,
    PingStatus? status,
    bool? isConnected,
    double? downloadSpeed,
    bool? isTestingSpeed,
    bool? isFavorite,
  }) {
    return Server(
      rawConfig: rawConfig,
      id: id,
      name: name ?? this.name,
      ip: ip,
      port: port,
      type: type,
      ping: ping ?? this.ping,
      status: status ?? this.status,
      isConnected: isConnected ?? this.isConnected,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      isTestingSpeed: isTestingSpeed ?? this.isTestingSpeed,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  /// **IMPROVED & ROBUST PARSING METHOD**
  static Server? fromConfigString(
    String config, {
    ServerType type = ServerType.ivpn,
  }) {
    if (config.isEmpty) return null;

    try {
      final uri = Uri.parse(config);
      String host = uri.host;
      int port = uri.port;
      String name = '#';

      if (uri.hasFragment && uri.fragment.isNotEmpty) {
        name = Uri.decodeComponent(uri.fragment).trim();
      }

      // Handle cases where host/port might be in userInfo for some formats
      if (uri.userInfo.isNotEmpty && (host.isEmpty || port == 0)) {
        final userInfoParts = uri.userInfo.split('@');
        if (userInfoParts.length > 1) {
          final addressParts = userInfoParts.last.split(':');
          if (addressParts.length == 2) {
            host = addressParts[0];
            port = int.tryParse(addressParts[1]) ?? 0;
          }
        }
      }

      // A final check to ensure we have the essential parts
      if (host.isEmpty || port == 0) {
        print("Could not extract host or port from config: $config");
        return null;
      }

      return Server(
        rawConfig: config,
        id: '$host:$port',
        name: name,
        ip: host,
        port: port,
        type: type,
      );
    } catch (e) {
      print("Failed to parse server config: $config, Error: $e");
      return null;
    }
  }
}
