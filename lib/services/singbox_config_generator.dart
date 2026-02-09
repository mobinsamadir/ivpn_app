
import 'dart:convert';
import 'dart:math';
import '../utils/file_logger.dart';
import '../utils/extensions.dart';

class SingboxConfigGenerator {
  // Ports
  static const int LOCAL_SOCKS_PORT = 10808;
  static const int LOCAL_HTTP_PORT = 10809;
  
  static final List<String> FINGERPRINTS = ['chrome', 'firefox', 'edge', 'safari', '360', 'qq'];
  static final Random _rng = Random();

  // Optimization: Reuse regex to avoid recompilation
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  // Optimization: Static list to prevent allocation on every config generation (hundreds of strings)
  static const List<String> _adDomains = [
    "adsterra.com", "google.com", "doubleclick.net", "googlesyndication.com", "googletagmanager.com",
    "facebook.com", "fbcdn.net", "twitter.com", "youtube.com", "ytimg.com", "googleadservices.com",
    "googletagservices.com", "google-analytics.com", "analytics.google.com", "googleapis.com",
    "gstatic.com", "gvt1.com", "gvt2.com", "2mdn.net", "googlesyndication.com", "doubleclickbygoogle.com",
    "googleoptimize.com", "googledomains.com", "googletraveladservices.com", "googlevads.com",
    "googleusercontent.com", "googlevideo.com", "googleweblight.com", "googlezip.net", "g.co", "goo.gl",
    "youtube-nocookie.com", "youtubeeducation.com", "youtubekids.com", "yt.be", "googlemail.com",
    "gmail.com", "google-analytics.com", "googleadservices.com", "googlecommerce.com", "googlecode.com",
    "googlebot.com", "blogspot.com", "blogspot.ae", "blogspot.al", "blogspot.am", "blogspot.ba",
    "blogspot.be", "blogspot.bg", "blogspot.bj", "blogspot.ca", "blogspot.cf", "blogspot.ch",
    "blogspot.cl", "blogspot.co.at", "blogspot.co.id", "blogspot.co.il", "blogspot.co.ke",
    "blogspot.co.nz", "blogspot.co.uk", "blogspot.co.za", "blogspot.com", "blogspot.com.ar",
    "blogspot.com.au", "blogspot.com.br", "blogspot.com.by", "blogspot.com.co", "blogspot.com.cy",
    "blogspot.com.ee", "blogspot.com.eg", "blogspot.com.es", "blogspot.com.mt", "blogspot.com.ng",
    "blogspot.com.tr", "blogspot.com.uy", "blogspot.cv", "blogspot.cz", "blogspot.de", "blogspot.dk",
    "blogspot.fi", "blogspot.fr", "blogspot.gr", "blogspot.hk", "blogspot.hr", "blogspot.hu",
    "blogspot.ie", "blogspot.in", "blogspot.is", "blogspot.it", "blogspot.jp", "blogspot.kr",
    "blogspot.li", "blogspot.lt", "blogspot.lu", "blogspot.lv", "blogspot.md", "blogspot.mk",
    "blogspot.mx", "blogspot.my", "blogspot.nl", "blogspot.no", "blogspot.pe", "blogspot.pt",
    "blogspot.qa", "blogspot.re", "blogspot.ro", "blogspot.rs", "blogspot.ru", "blogspot.se",
    "blogspot.sg", "blogspot.si", "blogspot.sk", "blogspot.sn", "blogspot.td", "blogspot.tw",
    "blogspot.ug", "blogspot.vn"
  ];

  static String generateConfig(String rawLink, {int listenPort = 10808, bool isTest = false}) {
    final socksPort = listenPort;
    final httpPort = listenPort + 1;
    final link = rawLink.trim();
    FileLogger.log("--- Parsing Protocol: ${link.split('://').first} ---");

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
      rethrow;
    }
  }

  /// Dedicated Ping Config - Minimal structure to avoid conflicts
  static String generatePingConfig({required String rawLink, int listenPort = 10808}) {
      return generateConfig(rawLink, listenPort: listenPort, isTest: true);
  }

  static String _parseVmess(String link, {required int socksPort, required int httpPort, required bool isTest}) {
    // Optimization: Use pre-compiled regex
    String encoded = link.substring(8).replaceAll(_whitespaceRegex, '');
    int mod = encoded.length % 4;
    if (mod > 0) encoded += '=' * (4 - mod);

    final String decoded = utf8.decode(base64Decode(encoded));
    final Map<String, dynamic> data = jsonDecode(decoded);

    final Map<String, dynamic> outbound = {
      "type": "vmess",
      "tag": "proxy",
      "server": data['add'],
      "server_port": int.parse(data['port'].toString()),
      "uuid": data['id'],
      "alter_id": int.tryParse(data['aid']?.toString() ?? '0') ?? 0,
      "security": "auto",
      "connect_timeout": isTest ? "5s" : "15s",
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
        "insecure": isTest,
      };
    }

    return _assembleFinalConfig(outbound, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
  }

  static String _parseUriStandard(String link, {required int socksPort, required int httpPort, required bool isTest}) {
    print('[CONFIG-GEN] Parsing standard URI: ${link.substring(0, link.length > 30 ? 30 : link.length)}...');
    
    if (!link.contains('?')) {
      print('⚠️ [CONFIG-GEN] WARNING: Link missing query parameters (?). This might be truncated: $link');
    }
    
    final uri = Uri.parse(link);
    final protocol = uri.scheme;
    final String userInfo = uri.userInfo;
    final String host = uri.host;
    final int port = uri.port;
    final Map<String, String> params = uri.queryParameters;
    final String security = params['security'] ?? "none";

    if (protocol == "vless") {
      print('[CONFIG-GEN] VLESS Security: $security');
      print('[CONFIG-GEN] VLESS Full params: $params');
      print('[CONFIG-GEN] VLESS Type: ${params['type']}');
      print('[CONFIG-GEN] VLESS ALPN: ${params['alpn']}');
    }

    final Map<String, dynamic> outbound = {
      "type": protocol,
      "tag": "proxy",
      "server": host,
      "server_port": port,
      "connect_timeout": isTest ? "5s" : "15s",
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
              : FINGERPRINTS[_rng.nextInt(FINGERPRINTS.length)]
        }
      };
      
      // Add ALPN if present (important for h2/h3)
      if (params.containsKey('alpn')) {
        tls["alpn"] = params['alpn']!.split(',');
      } else if (protocol == "vless") {
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
        tls["reality"] = {
          "enabled": true,
          "public_key": params['pbk'] ?? "",
          "short_id": params['sid'] ?? "",
          "spider_x": params['spx'] ?? ""
        };
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

    try {
      String encoded = jsonEncode(outbound);
      String preview = encoded.length > 200 ? "${encoded.substring(0, 200)}..." : encoded;
      print('[CONFIG-GEN] Generated ${protocol.toUpperCase()} outbound: $preview');
    } catch (e) {
      print('[CONFIG-GEN] Error logging config: $e');
    }
    return _assembleFinalConfig(outbound, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
  }

  static String _parseShadowsocks(String link, {required int socksPort, required int httpPort, required bool isTest}) {
    String content = link.substring(5);
    String method, password, host;
    int port;

    if (content.contains('@')) {
      final parts = content.split('@');
      final authParts = utf8.decode(base64Decode(parts[0])).split(':');
      method = authParts[0];
      password = authParts[1];
      final serverParts = parts[1].split(':');
      host = serverParts[0].split('#').first;
      port = int.parse(serverParts[1].split('#').first);
    } else {
      final decoded = utf8.decode(base64Decode(content.split('#').first));
      final mainParts = decoded.split('@');
      final authParts = mainParts[0].split(':');
      method = authParts[0];
      password = authParts[1];
      final serverParts = mainParts[1].split(':');
      host = serverParts[0];
      port = int.parse(serverParts[1]);
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

    try {
      print('[CONFIG-GEN] Generated SHADOWSOCKS outbound: ${jsonEncode(outbound)}');
    } catch (e) {
      print('[CONFIG-GEN] Error logging SS config: $e');
    }
    return _assembleFinalConfig(outbound, socksPort: socksPort, httpPort: httpPort, isTest: isTest);
  }

  /// Extracts host and port for pre-flight TCP checks
  static Map<String, dynamic>? extractServerDetails(String link) {
    try {
      final uri = Uri.tryParse(link);
      if (uri == null) return null;

      if (link.toLowerCase().startsWith('vmess://')) {
        // Optimization: Use pre-compiled regex
        String encoded = link.substring(8).replaceAll(_whitespaceRegex, '');
        int mod = encoded.length % 4;
        if (mod > 0) encoded += '=' * (4 - mod);
        final String decoded = utf8.decode(base64Decode(encoded));
        final Map<String, dynamic> data = jsonDecode(decoded);
        return {
          'host': data['add'],
          'port': int.tryParse(data['port']?.toString() ?? '443') ?? 443
        };
      } 
      
      if (link.toLowerCase().startsWith('ss://')) {
        String content = link.substring(5);
        String host;
        int port;

        if (content.contains('@')) {
          final parts = content.split('@');
          final serverParts = parts[1].split(':');
          host = serverParts[0].split('#').first;
          port = int.parse(serverParts[1].split('#').first);
        } else {
          final decoded = utf8.decode(base64Decode(content.split('#').first));
          final mainParts = decoded.split('@');
          final serverParts = mainParts[1].split(':');
          host = serverParts[0];
          port = int.parse(serverParts[1]);
        }
        return {'host': host, 'port': port};
      }

      // VLESS / Trojan / generic URI
      return {
        'host': uri.host,
        'port': uri.effectivePort
      };
    } catch (e) {
      print('[CONFIG-GEN] Error extracting server details: $e');
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
        "level": "info",
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
            "domain_suffix": _adDomains,
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
