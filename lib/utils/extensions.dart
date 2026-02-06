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
