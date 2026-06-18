# ivpn_new

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/mobinsamadir/ivpn_app)

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
"# ivpn_new1" 

## Important Files Reference

| File | Purpose | GitHub Link |
|---|---|---|
| `android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt` | Native VPN Service handling routing and tunneling | [SingboxVpnService.kt](https://github.com/mobinsamadir/ivpn_app/blob/main/android/app/src/main/kotlin/com/example/ivpn_new/SingboxVpnService.kt) |
| `android/app/src/main/kotlin/com/example/ivpn_new/MainActivity.kt` | Main entry point for native Android app, handles event channels | [MainActivity.kt](https://github.com/mobinsamadir/ivpn_app/blob/main/android/app/src/main/kotlin/com/example/ivpn_new/MainActivity.kt) |
| `lib/screens/connection_home_screen.dart` | Main UI for connecting to VPN and displaying stats | [connection_home_screen.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/screens/connection_home_screen.dart) |
| `lib/services/config_manager.dart` | Manages VPN configurations, blacklists, and lists | [config_manager.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/config_manager.dart) |
| `lib/services/funnel_service.dart` | Service for sequential stage testing (TCP, HTTP, Speed) | [funnel_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/funnel_service.dart) |
| `lib/services/native_vpn_service.dart` | Dart bridge to Native VPN Service | [native_vpn_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/native_vpn_service.dart) |
| `.github/workflows/main_pipeline.yml` | CI Pipeline configuration | [main_pipeline.yml](https://github.com/mobinsamadir/ivpn_app/blob/main/.github/workflows/main_pipeline.yml) |
| `lib/services/config_gist_service.dart` | Controls subscription URLs and updates | [config_gist_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/config_gist_service.dart) |
| `lib/services/ad_manager_service.dart` | Controls Ad config and persistence | [ad_manager_service.dart](https://github.com/mobinsamadir/ivpn_app/blob/main/lib/services/ad_manager_service.dart) |
