# Project Directory Tree

```
./
    .flutter-plugins-dependencies
    .gitignore
    .metadata
    README.md
    analysis_options.yaml
    configs_reference.txt
    crash_log.txt
    debug_config.json
    debug_singbox.ps1
    debug_vmess.ps1
    docker-compose.yml
    folder_tree.json
    folder_tree.txt
    generate_tree.py
    manual_build.ps1
    manual_build_backup.ps1
    plan.md
    pubspec.lock
    pubspec.yaml
    run_vpn.ps1
    run_with_logs.ps1
    sources.txt
    ss_test.json
    test_adaptive_manual.ps1
    test_minimal_config.json
    test_proxy.ps1
    test_uri_opaque.dart
    test_vless_manual.ps1
    view_logs.ps1
    vless_manual_test.json
    vless_test.json
    vmess_debug.json
    vmess_test.json
    ios/
        .gitignore
        Runner.xcworkspace/
            contents.xcworkspacedata
            xcshareddata/
                IDEWorkspaceChecks.plist
                WorkspaceSettings.xcsettings
        Flutter/
            AppFrameworkInfo.plist
            Debug.xcconfig
            Release.xcconfig
        Runner/
            AppDelegate.swift
            Info.plist
            Runner-Bridging-Header.h
            Assets.xcassets/
                AppIcon.appiconset/
                    Contents.json
                    Icon-App-1024x1024@1x.png
                    Icon-App-20x20@1x.png
                    Icon-App-20x20@2x.png
                    Icon-App-20x20@3x.png
                    Icon-App-29x29@1x.png
                    Icon-App-29x29@2x.png
                    Icon-App-29x29@3x.png
                    Icon-App-40x40@1x.png
                    Icon-App-40x40@2x.png
                    Icon-App-40x40@3x.png
                    Icon-App-50x50@1x.png
                    Icon-App-50x50@2x.png
                    Icon-App-57x57@1x.png
                    Icon-App-57x57@2x.png
                    Icon-App-60x60@2x.png
                    Icon-App-60x60@3x.png
                    Icon-App-72x72@1x.png
                    Icon-App-72x72@2x.png
                    Icon-App-76x76@1x.png
                    Icon-App-76x76@2x.png
                    Icon-App-83.5x83.5@2x.png
                LaunchImage.imageset/
                    Contents.json
                    LaunchImage.png
                    LaunchImage@2x.png
                    LaunchImage@3x.png
                    README.md
            Base.lproj/
                LaunchScreen.storyboard
                Main.storyboard
        RunnerTests/
            RunnerTests.swift
        Runner.xcodeproj/
            project.pbxproj
            xcshareddata/
                xcschemes/
                    Runner.xcscheme
            project.xcworkspace/
                contents.xcworkspacedata
                xcshareddata/
                    IDEWorkspaceChecks.plist
                    WorkspaceSettings.xcsettings
    config-refinery/
        README.md
        build.bat
        go.mod
        go.sum
        main.go
        master_configs.txt
        run.bat
        subs.txt
        internal/
            scanner/
                scanner.go
            dedup/
                dedup.go
            utils/
                utils.go
            tester/
                tester.go
            wifi/
                wifi.go
            parser/
                parser.go
            storage/
                storage.go
            inputs/
                1.txt
                F0rc3Run_V2Ray.txt
                httpsraw.githubusercontent.comEpodoniosv2ray-configsmainAll_Configs_Sub.txt
                subs.txt
            types/
                types.go
        output/
            1_all_parsed.txt
            2_unique.txt
            3_live_l4.txt
            Ethernet_Or_Unknown_Final.txt
            Export_2026-01-28_20-59.txt
            Export_2026-02-04_18-23.txt
    test/
        services/
            access_manager_test.dart
            ad_manager_service_test.dart
            config_gist_service_test.dart
            config_manager_smart_logic_test.dart
            config_manager_test.dart
            config_parser_test.dart
            connectivity_service_test.dart
            ephemeral_tester_test.dart
            funnel_service_test.dart
            native_vpn_service_test.dart
            reality_parser_test.dart
            singbox_config_generator_test.dart
            smart_pinger_test.dart
            time_wallet_service_test.dart
            windows_vpn_service_test.dart
        utils/
            base64_utils_test.dart
            cancellable_operation_test.dart
            cleanup_utils_test.dart
            clipboard_utils_test.dart
            connectivity_utils_test.dart
            port_allocator_test.dart
        widgets/
            config_card_test.dart
            shimmer_config_card_test.dart
        performance/
            config_hash_benchmark_test.dart
        screens/
            connection_home_screen_test.dart
    configs/
        analysis_options.yaml
        configs_reference.txt
        debug_config.json
        folder_tree.json
        folder_tree.txt
        pubspec.lock
        pubspec_backup.yaml
        vmess_debug.json
    windows/
        .gitignore
        CMakeLists.txt
        flutter/
            CMakeLists.txt
            generated_plugin_registrant.cc
            generated_plugin_registrant.h
            generated_plugins.cmake
        runner/
            CMakeLists.txt
            Runner.rc
            flutter_window.cpp
            flutter_window.h
            main.cpp
            resource.h
            runner.exe.manifest
            utils.cpp
            utils.h
            win32_window.cpp
            win32_window.h
            resources/
                app_icon.ico
    android/
        .gitignore
        build.gradle.kts
        gradle.properties
        gradlew
        gradlew.bat
        settings.gradle.kts
        app/
            build.gradle.kts
            proguard-rules.pro
            src/
                debug/
                    AndroidManifest.xml
                profile/
                    AndroidManifest.xml
                main/
                    AndroidManifest.xml
                    res/
                        values/
                            styles.xml
                        mipmap-hdpi/
                            ic_launcher.png
                        mipmap-mdpi/
                            ic_launcher.png
                        drawable/
                            launch_background.xml
                        mipmap-xxxhdpi/
                            ic_launcher.png
                        mipmap-xhdpi/
                            ic_launcher.png
                        mipmap-xxhdpi/
                            ic_launcher.png
                        xml/
                            provider_paths.xml
                        drawable-v21/
                            launch_background.xml
                        values-night/
                            styles.xml
                    kotlin/
                        com/
                            example/
                                ivpnnew/
                                    SingboxVpnService.kt
                                ivpn_new/
                                    MainActivity.kt
        gradle/
            wrapper/
                gradle-wrapper.jar
                gradle-wrapper.properties
    docker/
        Dockerfile.android
        Dockerfile.windows
    web/
        favicon.png
        index.html
        manifest.json
        icons/
            Icon-192.png
            Icon-512.png
            Icon-maskable-192.png
            Icon-maskable-512.png
    docs/
        AGENT_KNOWLEDGE.md
        SECURITY_AND_INSIGHTS.md
        SINGBOX_TOOLING_NOTES.md
        TESTING_AUDIT.md
        VPN_CORE_BUILD_NOTES.md
        WORKFLOWS_INVENTORY.md
    integration_test/
        vpn_lifecycle_test.dart
    scripts/
        build_all.ps1
        build_direct.ps1
        build_with_ninja.ps1
        build_with_vs2022.ps1
        clean_windows_build.sh
        final_build_solution.ps1
        force_build.ps1
        run_vpn.ps1
        run_with_logs.ps1
        simple_build.ps1
        verify_build.py
        view_logs.ps1
        vs2026_build.ps1
    packages/
        screen_retriever_windows/
            CHANGELOG.md
            LICENSE
            README.md
            analysis_options.yaml
            pubspec.yaml
            windows/
                CMakeLists.txt
                screen_retriever_windows_plugin.cpp
                screen_retriever_windows_plugin.h
                screen_retriever_windows_plugin_c_api.cpp
                test/
                    screen_retriever_windows_plugin_test.cpp
                include/
                    screen_retriever_windows/
                        screen_retriever_windows_plugin_c_api.h
        window_manager/
            .gitignore
            .metadata
            CHANGELOG.md
            LICENSE
            README-ZH.md
            README.md
            dart_dependency_validator.yaml
            pubspec.yaml
            test/
                window_manager_test.dart
            windows/
                .gitignore
                CMakeLists.txt
                window_manager.cpp
                window_manager_plugin.cpp
                include/
                    window_manager/
                        window_manager_plugin.h
            linux/
                CMakeLists.txt
                window_manager_plugin.cc
                include/
                    window_manager/
                        window_manager_plugin.h
            lib/
                window_manager.dart
                src/
                    resize_edge.dart
                    title_bar_style.dart
                    window_listener.dart
                    window_manager.dart
                    window_options.dart
                    utils/
                        calc_window_position.dart
                    widgets/
                        drag_to_move_area.dart
                        drag_to_resize_area.dart
                        virtual_window_frame.dart
                        window_caption.dart
                        window_caption_button.dart
            macos/
                window_manager.podspec
                window_manager/
                    Package.swift
                    Sources/
                        window_manager/
                            WindowManager.swift
                            WindowManagerPlugin.swift
        permission_handler_windows/
            AUTHORS
            CHANGELOG.md
            LICENSE
            README.md
            pubspec.yaml
            windows/
                CMakeLists.txt
                permission_constants.h
                permission_handler_windows_plugin.cpp
                include/
                    permission_handler_windows/
                        permission_handler_windows_plugin.h
    linux/
        .gitignore
        CMakeLists.txt
        flutter/
            CMakeLists.txt
            generated_plugin_registrant.cc
            generated_plugin_registrant.h
            generated_plugins.cmake
        runner/
            CMakeLists.txt
            main.cc
            my_application.cc
            my_application.h
    assets/
        geoip.db
        geosite.db
        icon.png
        html/
            placeholder_ad.html
        executables/
            windows/
                geoip.db
                geosite.db
                sing-box.exe
    lib/
        main.dart
        services/
            access_manager.dart
            ad_manager_interface.dart
            ad_manager_io.dart
            ad_manager_service.dart
            ad_manager_stub.dart
            ad_manager_web.dart
            background_ad_service.dart
            binary_manager.dart
            config_gist_service.dart
            config_manager.dart
            config_parser.dart
            connectivity_service.dart
            fallback_strategy.dart
            ffi_utils.dart
            funnel_service.dart
            native_vpn_service.dart
            singbox_config_generator.dart
            smart_pinger.dart
            storage_interface.dart
            test_job.dart
            test_orchestrator.dart
            test_queue.dart
            time_wallet_service.dart
            windows_vpn_service.dart
            testers/
                adaptive_speed_tester.dart
                ephemeral_tester.dart
                health_checker.dart
                stability_monitor.dart
                test_manager.dart
        utils/
            advanced_logger.dart
            base64_utils.dart
            cancellable_operation.dart
            chart_utils.dart
            cleanup_utils.dart
            clipboard_utils.dart
            connectivity_utils.dart
            endpoints.dart
            file_logger.dart
            logger.dart
            port_allocator.dart
            test_constants.dart
        widgets/
            ad_dialog.dart
            ad_explanation_dialog.dart
            config_card.dart
            full_screen_ad_dialog.dart
            scale_on_tap.dart
            shimmer_config_card.dart
            shimmer_list.dart
            sliver_tab_bar_delegate.dart
            smart_connect_button.dart
            universal_ad_widget.dart
            update_dialog.dart
        models/
            ad_config.dart
            vpn_config_with_metrics.dart
            testing/
                test_results.dart
        providers/
            theme_provider.dart
        screens/
            about_screen.dart
            connection_home_screen.dart
            log_viewer_screen.dart
            settings_screen.dart
            splash_screen.dart
    macos/
        .gitignore
        Runner.xcworkspace/
            contents.xcworkspacedata
            xcshareddata/
                IDEWorkspaceChecks.plist
        Flutter/
            Flutter-Debug.xcconfig
            Flutter-Release.xcconfig
            GeneratedPluginRegistrant.swift
        Runner/
            AppDelegate.swift
            DebugProfile.entitlements
            Info.plist
            MainFlutterWindow.swift
            Release.entitlements
            Assets.xcassets/
                AppIcon.appiconset/
                    Contents.json
                    app_icon_1024.png
                    app_icon_128.png
                    app_icon_16.png
                    app_icon_256.png
                    app_icon_32.png
                    app_icon_512.png
                    app_icon_64.png
            Configs/
                AppInfo.xcconfig
                Debug.xcconfig
                Release.xcconfig
                Warnings.xcconfig
            Base.lproj/
                MainMenu.xib
        RunnerTests/
            RunnerTests.swift
        Runner.xcodeproj/
            project.pbxproj
            xcshareddata/
                xcschemes/
                    Runner.xcscheme
            project.xcworkspace/
                xcshareddata/
                    IDEWorkspaceChecks.plist
    tool/
        core_version.txt
        pre_pr_check.sh
        setup_core.dart
        update_version.dart
```

# pubspec.yaml

```yaml
name: ivpn_new
description: iVPN Client - High Performance VPN
version: 1.0.0+1771954304

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  # Networking & API
  html: ^0.15.4
  dio: ^5.7.0
  http: ^1.2.2
  connectivity_plus: ^6.1.0

  # UI & State Management
  provider: ^6.1.2
  window_manager: ^0.5.1
  screen_retriever: ^0.2.1
  webview_flutter: ^4.9.0
  flutter_markdown: ^0.7.4 # اضافه شد برای رفع ارور دیالوگ آپدیت

  # Media & Ads
  video_player: ^2.8.6
  chewie: ^1.8.1
  cached_network_image: ^3.3.1
  logger: ^2.2.0

  # Utilities & Storage
  path_provider: ^2.1.5
  path: ^1.9.0
  file_picker: ^8.1.4
  device_info_plus: ^11.1.0
  url_launcher: ^6.3.1
  shared_preferences: ^2.3.2
  crypto: ^3.0.5
  package_info_plus: ^8.0.0
  pub_semver: ^2.1.4
  permission_handler: ^12.0.3
  collection: ^1.17.0

  # File Opening (Fixed for Android)
  open_file: ^3.5.10 # جایگزین نسخه Plus شد

  meta: ^1.9.0
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_launcher_icons: ^0.14.2
  flutter_lints: ^5.0.0
  build_runner: ^2.4.13
  mockito: ^5.4.4

  # Build Script Requirements (حیاتی برای setup_core.dart)
  archive: ^3.6.1
  mocktail: ^1.0.4
  fake_async: ^1.3.3
  clock: ^1.1.2
  integration_test:
    sdk: flutter

# تنظیمات آیکون
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/icon.png"
  windows:
    generate: true
    image_path: "assets/icon.png"
    icon_size: 48

flutter:
  uses-material-design: true
  assets:
    - assets/icon.png
    # Windows Assets
    - assets/executables/windows/sing-box.exe
    - assets/executables/windows/geoip.db
    - assets/executables/windows/geosite.db
    # Generic Assets
    - assets/geoip.db
    - assets/geosite.db
    - assets/html/


dependency_overrides:
  window_manager:
    path: packages/window_manager
  permission_handler_windows:
    path: packages/permission_handler_windows
  screen_retriever_windows:
    path: packages/screen_retriever_windows
```
