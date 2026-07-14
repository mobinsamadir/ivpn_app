import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivpn_new/providers/theme_provider.dart';

void main() {
  group('ThemeProvider', () {
    test('initial theme is ThemeMode.system', () {
      final provider = ThemeProvider();
      expect(provider.themeMode, ThemeMode.system);
    });

    test(
        'toggleTheme(true) sets theme to ThemeMode.dark and notifies listeners',
        () {
      final provider = ThemeProvider();
      var notified = false;
      provider.addListener(() {
        notified = true;
      });

      provider.toggleTheme(true);

      expect(provider.themeMode, ThemeMode.dark);
      expect(notified, isTrue);
    });

    test(
        'toggleTheme(false) sets theme to ThemeMode.light and notifies listeners',
        () {
      final provider = ThemeProvider();
      var notified = false;
      provider.addListener(() {
        notified = true;
      });

      provider.toggleTheme(false);

      expect(provider.themeMode, ThemeMode.light);
      expect(notified, isTrue);
    });
  });
}
