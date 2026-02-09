// lib/utils/extensions.dart

import 'package:flutter/material.dart';
import '../models/server_model.dart';

/// An extension to add UI-related helpers to the [PingStatus] enum.
extension PingStatusUI on PingStatus {
  /// Returns a specific color based on the ping status.
  Color get color {
    switch (this) {
      case PingStatus.good:
        return Colors.green;
      case PingStatus.medium:
        return Colors.orange;
      case PingStatus.bad:
        return Colors.red;
      case PingStatus.unknown:
        return Colors.grey;
    }
  }
}

/// Extension on [Uri] to provide effective port calculation.
extension UriPortExtension on Uri {
  /// Returns the port if it's explicitly specified (not 0),
  /// otherwise returns the default port for the scheme.
  int get effectivePort {
    if (port != 0) return port;

    switch (scheme.toLowerCase()) {
      case 'https':
      case 'vmess':
      case 'vless':
      case 'trojan':
        return 443;
      case 'ss':
        return 8388;
      case 'http':
      default:
        return 80;
    }
  }
}
