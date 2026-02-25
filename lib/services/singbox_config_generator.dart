
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart'; // For kDebugMode
import '../utils/advanced_logger.dart';
import '../utils/file_logger.dart';
import '../utils/base64_utils.dart';

class SingboxConfigGenerator {
  // Ports
  static const int localSocksPort = 10808;
  static const int localHttpPort = 10809;
  
  static final List<String> fingerprints = ['chrome', 'firefox', 'edge', 'safari', '360', 'qq'];
  static final Random _rng = Random();

  // REMOVED default listenPort=10808 to force dynamic port usage
  static String generateConfig(String rawLink, {required int listenPort, bool isTest = false}) {
    final socksPort = listenPort;
    final httpPort = listenPort + 1;
    final link = rawLink.trim();
    if (kDebugMode) {
      FileLogger.log("--- Parsing Protocol: ${link.split('://').first} ---");
    }

    try {
      if (link.toLowerCase().startsWith('vmess://')) {
        return _parseVmess(link, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
      } else if (link.toLowerCase().startsWith('vless://') || link.toLowerCase().startsWith('trojan://')) {
        return _parseUriStandard(link, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
      } else if (link.toLowerCase().startsWith('ss://')) {
        return _parseShadowsocks(link, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
      } else {
        throw Exception("Unsupported protocol: ${link.split('://').first}");
      }
    } catch (e) {
      FileLogger.log("❌ ERROR: Protocol parsing failed: $e");
      AdvancedLogger.warn("[PARSER-FAIL] Raw URL: $link");
      rethrow;
    }
  }

  /// Dedicated Ping Config - Minimal structure to avoid conflicts
  static String generatePingConfig({required String rawLink, required int listenPort}) {
      return generateConfig(rawLink, listenPort: listenPort, isTest: true);
  }

  static String _parseVmess(String link, {required int socksPort, required int httpPort, required bool isTest}) {
    final String decoded = Base64Utils.safeDecode(link.substring(8));
    if (decoded.isEmpty) throw FormatException("Invalid VMess Base64");

    final Map<String, dynamic> data = jsonDecode(decoded);

    final Map<String, dynamic> outbound = {
      "type": "vmess",
      "tag": "proxy",
      "server": data['add'],
      "server_port": int.tryParse(data['port'].toString()) ?? 443,
      "uuid": data['id'],
      "alter_id": int.tryParse(data['aid']?.toString() ?? '0') ?? 0,
      "security": "auto",
      "connect_timeout": isTest ? "5s" : "15s",
      "multiplex": {
        "enabled": false,
        "padding": true,
        "protocol": "h2mux",
        "max_connections": 4,
        "min_streams": 2
      },
    };

    final transport = _buildSingBoxTransport(
      network: data['net'] ?? "tcp",
      path: data['path'] ?? "/",
      host: data['host'] ?? "",
    );
    if (transport != null) outbound["transport"] = transport;

    if (data['tls'] == "tls") {
      outbound["tls"] = {
        "enabled": true,
        "server_name": data['sni'] ?? data['host'] ?? data['add'],
        "alpn": ["h2", "http/1.1"],
        "insecure": isTest,
      };
    }

    return _assembleFinalConfig(outbound, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
  }

  static String _parseUriStandard(String link, {required int socksPort, required int httpPort, required bool isTest}) {
    Uri? uri;
    try {
      uri = Uri.parse(link);
    } catch (e) {
      // Intentionally ignored, will handle manual parsing or fallback below
    }

    String? protocol;
    String? userInfo;
    String? host;
    int port = 443;
    Map<String, String> params = {};

    // 1. TRY STANDARD URI PARSING
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
       protocol = uri.scheme;
       userInfo = uri.userInfo;
       host = uri.host;
       port = uri.hasPort ? uri.port : 443;
       params = Map.from(uri.queryParameters); // Copy to allow modification
    }
    // 2. FALLBACK: MANUALLY PARSE IF URI FAILED OR LOOKS MALFORMED (e.g. Base64 block)
    // IMPORTANT: Check if protocol is vless/trojan but NOT followed by typical host (Base64 instead)
    if (host == null || (host.isNotEmpty && !host.contains('.') && !host.contains(':') && host.length > 20)) {
       final schemeSplit = link.split('://');
       if (schemeSplit.length == 2) {
          protocol = schemeSplit[0];
          final rest = schemeSplit[1];

          // Check if it's a Base64 blob (common in some subscription formats)
          final possibleBase64 = rest.split('#').first;

          if (!possibleBase64.contains('?') && !possibleBase64.contains('@')) {
             try {
                final decoded = Base64Utils.safeDecode(possibleBase64);
                if (decoded.startsWith('{')) {
                   final json = jsonDecode(decoded);
                   // Extract from JSON
                   host = json['add'];
                   port = int.tryParse(json['port']?.toString() ?? '443') ?? 443;
                   userInfo = json['id']; // UUID

                   // Map JSON fields to params expected by logic below
                   if (json['scy'] != null) params['security'] = json['scy'];
                   if (json['net'] != null) params['type'] = json['net'];
                   if (json['type'] != null) params['type'] = json['type']; // Sometimes 'type'
                   if (json['tls'] != null && json['tls'] != "none") params['security'] = json['tls'];

                   if (json['sni'] != null) params['sni'] = json['sni'];
                   if (json['host'] != null) params['host'] = json['host'];
                   if (json['path'] != null) params['path'] = json['path'];
                   if (json['pbk'] != null) params['pbk'] = json['pbk'];
                   if (json['sid'] != null) params['sid'] = json['sid'];
                   if (json['fp'] != null) params['fp'] = json['fp'];
                   if (json['alpn'] != null) params['alpn'] = json['alpn'];
                   if (json['flow'] != null) params['flow'] = json['flow'];
                }
             } catch (_) {
                // Not JSON or decode failed
             }
          }
       }
    }

    // 3. SPECIAL HANDLING: CASE-INSENSITIVE HOST for VLESS
    if (host != null && protocol != null && (protocol == 'vless' || protocol == 'trojan')) {
       if (uri != null) {
          try {
             final afterAt = link.split('@');
             if (afterAt.length > 1) {
                final hostPart = afterAt.last.split(RegExp(r'[:/?#]')).first;
                if (hostPart.toLowerCase() == host.toLowerCase()) {
                   host = hostPart; // Restore original casing
                }
             }
          } catch (_) {}
       }
    }

    // If still failed or host is empty (unparsed base64 that wasn't JSON)
    if (host == null || host.isEmpty || protocol == null) {
       // Fallback for non-standard URI parsing
       throw FormatException("Invalid URI or Config Format: $link");
    }

    final String security = params['security'] ?? "none";

    final Map<String, dynamic> outbound = {
      "type": protocol,
      "tag": "proxy",
      "server": host,
      "server_port": port,
      "connect_timeout": isTest ? "5s" : "15s",
      "multiplex": {
        "enabled": false,
        "padding": true,
        "protocol": "h2mux",
        "max_connections": 4,
        "min_streams": 2
      },
    };

    if (protocol == "vless") {
      outbound["uuid"] = userInfo;
      outbound["flow"] = params['flow'] ?? "";
    } else {
      // Trojan
      outbound["password"] = userInfo;
    }

    if (security == "tls" || security == "reality") {
      final tls = {
        "enabled": true,
        "server_name": params['sni'] ?? host,
        "utls": {
          "enabled": true, 
          "fingerprint": (params['fp'] != null && params['fp']!.isNotEmpty) 
              ? params['fp']! 
              : fingerprints[_rng.nextInt(fingerprints.length)]
        }
      };
      
      // Add ALPN if present (important for h2/h3)
      if (params.containsKey('alpn')) {
        tls["alpn"] = params['alpn']!.split(',');
      } else {
        // Default ALPN for Mux support
        tls["alpn"] = ["h2", "http/1.1"];
      }

      // Sanitize ALPN for WebSocket - Avoid h3 crash
      if (params['type'] == 'ws' && tls.containsKey('alpn')) {
        final List<String> alpnList = List<String>.from(tls['alpn'] as List);
        if (alpnList.contains('h3')) {
          alpnList.remove('h3');
          if (alpnList.isEmpty) alpnList.add('http/1.1');
          tls['alpn'] = alpnList;
        }
      }

      if (security == "reality") {
        final pbk = params['pbk'] ?? params['public_key'] ?? "";
        // VALIDATION: Prevent crash on invalid Reality configs
        if (pbk.trim().isEmpty) {
           // Fallback mechanism for missing PBK
           AdvancedLogger.warn('[PARSER-WARNING] PBK missing, attempting standard VLESS for URL: $link');
           // Do not add reality block, effectively falling back to standard TLS if configured
        } else {
           tls["reality"] = {
             "enabled": true,
             "public_key": pbk,
             "short_id": params['sid'] ?? ""
           };
        }
      }
      tls["insecure"] = isTest;
      outbound["tls"] = tls;
    }

    final String transportType = params['type'] ?? "tcp";
    final transport = _buildSingBoxTransport(
      network: transportType,
      path: params['path'] ?? "/",
      host: params['host'] ?? "",
      serviceName: params['serviceName'],
    );
    if (transport != null) outbound["transport"] = transport;

    return _assembleFinalConfig(outbound, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
  }

  static String _parseShadowsocks(String link, {required int socksPort, required int httpPort, required bool isTest}) {
    String content = link.substring(5);
    String method, password, host;
    int port;

    if (content.contains('@')) {
      final parts = content.split('@');
      final decodedAuth = Base64Utils.safeDecode(parts[0]);
      if (decodedAuth.isEmpty) throw FormatException("Invalid SS Auth Base64");

      final authParts = decodedAuth.split(':');
      method = authParts[0];
      password = authParts[1];
      final serverParts = parts[1].split(':');
      host = serverParts[0].split('#').first;
      port = int.tryParse(serverParts[1].split('#').first) ?? 443;
    } else {
      final decoded = Base64Utils.safeDecode(content.split('#').first);
      if (decoded.isEmpty) throw FormatException("Invalid SS Base64");

      final mainParts = decoded.split('@');
      final authParts = mainParts[0].split(':');
      method = authParts[0];
      password = authParts[1];
      final serverParts = mainParts[1].split(':');
      host = serverParts[0];
      port = int.tryParse(serverParts[1]) ?? 443;
    }
    final Map<String, dynamic> outbound = {
      "type": "shadowsocks",
      "tag": "proxy",
      "server": host,
      "server_port": port,
      "method": method,
      "password": password,
      "connect_timeout": isTest ? "5s" : "15s",
    };

    // Parse Plugins (e.g. ss://.../?plugin=v2ray-plugin;mode=websocket;path=/;host=...)
    final Uri? parsedUri = Uri.tryParse(link);
    if (parsedUri != null && parsedUri.queryParameters.containsKey('plugin')) {
      final pluginRaw = parsedUri.queryParameters['plugin']!;
      final pluginParts = pluginRaw.split(';');
      final pluginName = pluginParts.first;
      
      final Map<String, String> pluginOpts = {};
      for (var part in pluginParts.skip(1)) {
        final kv = part.split('=');
        if (kv.length == 2) pluginOpts[kv[0]] = kv[1];
      }

      if (pluginName.contains('v2ray-plugin') || pluginOpts['mode'] == 'websocket') {
        outbound["transport"] = {
          "type": "ws",
          "path": pluginOpts['path'] ?? "/",
          "headers": {"Host": pluginOpts['host'] ?? ""}
        };
      } else if (pluginName.contains('obfs-local') || pluginOpts['obfs'] != null) {
         // Basic HTTP Obfs mapping if applicable
      }
    }

    return _assembleFinalConfig(outbound, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
  }

  /// Extracts host and port for pre-flight TCP checks
  static Map<String, dynamic>? extractServerDetails(String link) {
    try {
      final uri = Uri.tryParse(link);

      // 1. VMess (Base64 JSON)
      if (link.toLowerCase().startsWith('vmess://')) {
        final String decoded = Base64Utils.safeDecode(link.substring(8));
        if (decoded.isEmpty) return null;

        try {
          final Map<String, dynamic> data = jsonDecode(decoded);
          return {
            'host': data['add'],
            'port': int.tryParse(data['port']?.toString() ?? '443') ?? 443
          };
        } catch (_) {
          // If JSON decode fails, maybe it's not JSON (legacy format not supported)
          return null;
        }
      } 
      
      // 2. Shadowsocks (SS)
      if (link.toLowerCase().startsWith('ss://')) {
        try {
          String content = link.substring(5);
          String host;
          int port;

          if (content.contains('@')) {
            final parts = content.split('@');
            final serverParts = parts[1].split(':');
            host = serverParts[0].split('#').first;
            port = int.parse(serverParts[1].split('#').first);
          } else {
            final decoded = Base64Utils.safeDecode(content.split('#').first);
            if (decoded.isEmpty) return null;

            final mainParts = decoded.split('@');
            final serverParts = mainParts[1].split(':');
            host = serverParts[0];
            port = int.parse(serverParts[1]);
          }
          return {'host': host, 'port': port};
        } catch (_) {
          return null;
        }
      }

      // 3. Generic URI (VLESS / Trojan / Hysteria / etc)
      if (uri != null && uri.host.isNotEmpty) {
          return {
            'host': uri.host,
            'port': uri.port > 0 ? uri.port : 443
          };
      }

      return null;
    } catch (e) {
      FileLogger.log('[CONFIG-GEN] Error extracting server details: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _buildSingBoxTransport({
    required String network,
    String? path,
    String? host,
    String? serviceName,
  }) {
    if (network == "ws") {
      return {
        "type": "ws",
        "path": path,
        "headers": {"Host": host}
      };
    } else if (network == "grpc") {
      return {
        "type": "grpc", 
        "service_name": serviceName ?? path ?? "grpc"
      };
    }
    return null;
  }

  static String _assembleFinalConfig(Map<String, dynamic> proxyOutbound, {required int socksPort, required int httpPort, bool isTest = false}) {
    // 1. Base Structure (Common)
    final Map<String, dynamic> config = {
      "log": {
        "level": "trace",
        "output": isTest ? "stderr" : "box.log", // Explicit stderr for capture
        "timestamp": true
      },
      "outbounds": [
        proxyOutbound,
        {"type": "direct", "tag": "direct"},
        {"type": "dns", "tag": "dns-out"}
      ],
    };

    // 2. Mode-Specific Configuration
    if (isTest) {
      // TEST MODE: SOCKS/HTTP Inbounds (No interference with system)
      config["inbounds"] = [
        {
          "type": "socks",
          "tag": "socks-test",
          "listen": "127.0.0.1",
          "listen_port": socksPort
        },
        {
          "type": "http",
          "tag": "http-test",
          "listen": "127.0.0.1",
          "listen_port": httpPort
        }
      ];

      // Lightweight Routing for Tests
      config["route"] = {
        "rules": [
          {"outbound": "proxy", "network": ["tcp", "udp"]}
        ],
        "auto_detect_interface": true,
        "final": "proxy"
      };

      // Simple DNS for Tests
      config["dns"] = {
        "servers": [
          {"tag": "remote", "address": "8.8.8.8", "detour": "proxy"}
        ],
        "rules": [],
        "final": "remote"
      };
      
    } else {
      // PRODUCTION MODE: TUN Inbound (Full VPN)
      config["inbounds"] = [
        {
          "type": "tun",
          "tag": "tun-in",
          "inet4_address": "172.19.0.1/30",
          "auto_route": true,
          "strict_route": true,
          "stack": "system", // Optimized for Windows
          "sniff": true
        }
      ];

      // Robust DNS (Encrypted Remote, Direct Local)
      config["dns"] = {
        "servers": [
          {"tag": "google", "address": "8.8.8.8", "detour": "proxy"},
          {"tag": "local", "address": "local", "detour": "direct"}
        ],
        "rules": [
          {"outbound": "any", "server": "local"} // Fallback to local if needed, though 'final' handles main
        ],
        "final": "google",
        "strategy": "ipv4_only"
      };

      // Smart Routing Rules
      config["route"] = {
        "auto_detect_interface": true,
        "rules": [
          {"protocol": "dns", "outbound": "dns-out"},
          // Route ad domains through proxy to bypass censorship in restricted regions
          {
            "domain_suffix": ["adsterra.com", "google.com", "doubleclick.net", "googlesyndication.com", "googletagmanager.com", "facebook.com", "fbcdn.net", "twitter.com", "youtube.com", "ytimg.com", "googleadservices.com", "googletagservices.com", "google-analytics.com", "analytics.google.com", "googleapis.com", "gstatic.com", "gvt1.com", "gvt2.com", "2mdn.net", "googlesyndication.com", "doubleclickbygoogle.com", "googleoptimize.com", "googledomains.com", "googletraveladservices.com", "googlevads.com", "googleusercontent.com", "googlevideo.com", "googleweblight.com", "googlezip.net", "g.co", "goo.gl", "youtube-nocookie.com", "youtubeeducation.com", "youtubekids.com", "yt.be", "googlemail.com", "gmail.com", "google-analytics.com", "googleadservices.com", "googlecommerce.com", "googlecode.com", "googlebot.com", "blogspot.com", "blogspot.ae", "blogspot.al", "blogspot.am", "blogspot.ba", "blogspot.be", "blogspot.bg", "blogspot.bj", "blogspot.ca", "blogspot.cf", "blogspot.ch", "blogspot.cl", "blogspot.co.at", "blogspot.co.id", "blogspot.co.il", "blogspot.co.ke", "blogspot.co.nz", "blogspot.co.uk", "blogspot.co.za", "blogspot.com", "blogspot.com.ar", "blogspot.com.au", "blogspot.com.br", "blogspot.com.by", "blogspot.com.co", "blogspot.com.cy", "blogspot.com.ee", "blogspot.com.eg", "blogspot.com.es", "blogspot.com.mt", "blogspot.com.ng", "blogspot.com.tr", "blogspot.com.uy", "blogspot.cv", "blogspot.cz", "blogspot.de", "blogspot.dk", "blogspot.fi", "blogspot.fr", "blogspot.gr", "blogspot.hk", "blogspot.hr", "blogspot.hu", "blogspot.ie", "blogspot.in", "blogspot.is", "blogspot.it", "blogspot.jp", "blogspot.kr", "blogspot.li", "blogspot.lt", "blogspot.lu", "blogspot.lv", "blogspot.md", "blogspot.mk", "blogspot.mx", "blogspot.my", "blogspot.nl", "blogspot.no", "blogspot.pe", "blogspot.pt", "blogspot.qa", "blogspot.re", "blogspot.ro", "blogspot.rs", "blogspot.ru", "blogspot.se", "blogspot.sg", "blogspot.si", "blogspot.sk", "blogspot.sn", "blogspot.td", "blogspot.tw", "blogspot.ug", "blogspot.vn"],
            "outbound": "proxy"
          },
          // Use IP ranges instead of geoip for Iran and private networks to avoid DB issues
          {"ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8"], "outbound": "direct"},
        ],
        "final": "proxy"
      };
    }

    return jsonEncode(config);
  }
}
