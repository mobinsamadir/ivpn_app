import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/models/server_model.dart';
import 'package:ivpn_new/utils/extensions.dart';

void main() {
  group('PingStatusUI Extension Tests', () {
    test('PingStatus.good should return Colors.green', () {
      expect(PingStatus.good.color, Colors.green);
    });

    test('PingStatus.medium should return Colors.orange', () {
      expect(PingStatus.medium.color, Colors.orange);
    });

    test('PingStatus.bad should return Colors.red', () {
      expect(PingStatus.bad.color, Colors.red);
    });

    test('PingStatus.unknown should return Colors.grey', () {
      expect(PingStatus.unknown.color, Colors.grey);
    });
  });
}
