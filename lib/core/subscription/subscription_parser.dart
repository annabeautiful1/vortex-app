import 'dart:convert';
import 'package:dio/dio.dart';
import '../utils/logger.dart';
import '../config/build_config.dart';
import '../../shared/models/proxy_node.dart';

/// 订阅解析服务
/// 支持解析 Clash YAML, Base64, SIP008 格式
class SubscriptionParser {
  final Dio _dio;

  SubscriptionParser()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

  /// 从URL获取并解析订阅
  /// subType 参数可选，如果不传则使用 BuildConfig 中配置的订阅类型
  Future<List<ProxyNode>> parseFromUrl(String url, {String? subType}) async {
    try {
      // 使用传入的 subType 或 BuildConfig 中的配置
      final effectiveSubType = subType ?? BuildConfig.instance.subscriptionType;

      // 添加订阅类型参数
      String requestUrl = url;
      if (effectiveSubType.isNotEmpty &&
          !url.contains('flag=') &&
          !url.contains('clash=')) {
        final separator = url.contains('?') ? '&' : '?';

        if (BuildConfig.instance.isV2board) {
          // V2board: 使用 flag 参数
          requestUrl = '$url${separator}flag=$effectiveSubType';
        } else {
          // SSPanel: 使用 clash 参数
          requestUrl = '$url${separator}clash=$effectiveSubType';
        }
      }

      VortexLogger.subscription('fetch', requestUrl);

      final response = await _dio.get(
        requestUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': BuildConfig.instance.effectiveUserAgent},
        ),
      );

      final content = response.data.toString();
      return parse(content);
    } catch (e) {
      VortexLogger.e('Failed to fetch subscription', e);
      rethrow;
    }
  }

  /// 解析订阅内容
  List<ProxyNode> parse(String content) {
    // 尝试检测格式并解析
    final trimmed = content.trim();

    // 尝试 Clash YAML 格式
    if (trimmed.startsWith('proxies:') ||
        trimmed.contains('\nproxies:') ||
        trimmed.startsWith('port:') ||
        trimmed.startsWith('mixed-port:')) {
      return _parseClashYaml(content);
    }

    // 尝试 JSON 格式 (SIP008)
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return _parseSip008(content);
      } catch (_) {
        // 不是有效JSON，继续尝试其他格式
      }
    }

    // 尝试 Base64 格式
    try {
      final decoded = utf8.decode(base64.decode(trimmed));
      return _parseBase64Content(decoded);
    } catch (_) {
      // 不是有效Base64
    }

    // 尝试URI列表格式
    if (trimmed.contains('://')) {
      return _parseUriList(content);
    }

    VortexLogger.w('Unknown subscription format');
    return [];
  }

  /// 解析 Clash YAML 格式
  List<ProxyNode> _parseClashYaml(String content) {
    final nodes = <ProxyNode>[];

    try {
      // 简单的YAML解析 (不使用yaml包以减少依赖)
      // 查找 proxies: 部分
      final proxiesMatch = RegExp(
        r'proxies:\s*\n([\s\S]*?)(?=\n[a-z-]+:|$)',
      ).firstMatch(content);
      if (proxiesMatch == null) {
        VortexLogger.w('No proxies section found in Clash config');
        return nodes;
      }

      final proxiesSection = proxiesMatch.group(1) ?? '';
      final proxyBlocks = _splitYamlArray(proxiesSection);

      for (final block in proxyBlocks) {
        final node = _parseClashProxy(block);
        if (node != null) {
          nodes.add(node);
        }
      }

      VortexLogger.i('Parsed ${nodes.length} nodes from Clash YAML');
    } catch (e) {
      VortexLogger.e('Failed to parse Clash YAML', e);
    }

    return nodes;
  }

  /// 分割YAML数组
  List<String> _splitYamlArray(String content) {
    final blocks = <String>[];
    final lines = content.split('\n');
    StringBuffer currentBlock = StringBuffer();
    bool inBlock = false;

    for (final line in lines) {
      if (line.trimLeft().startsWith('- ')) {
        if (inBlock && currentBlock.isNotEmpty) {
          blocks.add(currentBlock.toString());
          currentBlock = StringBuffer();
        }
        inBlock = true;
        // 移除开头的 "- " 并保留后面的内容
        currentBlock.writeln(line.replaceFirst(RegExp(r'^\s*-\s*'), ''));
      } else if (inBlock && line.trim().isNotEmpty) {
        currentBlock.writeln(line);
      }
    }

    if (currentBlock.isNotEmpty) {
      blocks.add(currentBlock.toString());
    }

    return blocks;
  }

  /// 解析单个 Clash 代理配置
  ProxyNode? _parseClashProxy(String block) {
    try {
      final props = _parseYamlBlock(block);
      if (props.isEmpty) return null;

      final type = props['type'] as String?;
      if (type == null) return null;

      final protocol = _getProtocolType(type);
      if (protocol == null) return null;

      final name = props['name'] as String? ?? '';
      final server = props['server'] as String? ?? '';
      final port = _parseInt(props['port']) ?? 0;

      if (server.isEmpty || port == 0) return null;

      // 提取标签
      final tags = _extractTags(name);
      final multiplier = _extractMultiplier(name);

      // 构建设置
      final settings = Map<String, dynamic>.from(props);
      settings.remove('name');
      settings.remove('server');
      settings.remove('port');
      settings.remove('type');

      return ProxyNode(
        id: '${server}_$port',
        name: name,
        server: server,
        port: port,
        protocol: protocol,
        settings: settings,
        tags: tags,
        multiplier: multiplier,
      );
    } catch (e) {
      VortexLogger.w('Failed to parse proxy block: $e');
      return null;
    }
  }

  /// 解析YAML块为Map
  Map<String, dynamic> _parseYamlBlock(String block) {
    final props = <String, dynamic>{};
    final trimmedBlock = block.trim();

    // 检查是否为内联格式 { key: value, key: value }
    if (trimmedBlock.startsWith('{') && trimmedBlock.endsWith('}')) {
      return _parseInlineYaml(trimmedBlock);
    }

    // 标准缩进格式
    final lines = block.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final colonIndex = trimmed.indexOf(':');
      if (colonIndex == -1) continue;

      final key = trimmed.substring(0, colonIndex).trim();
      var value = trimmed.substring(colonIndex + 1).trim();

      // 移除引号
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }

      // 尝试转换类型
      if (value == 'true') {
        props[key] = true;
      } else if (value == 'false') {
        props[key] = false;
      } else if (int.tryParse(value) != null) {
        props[key] = int.parse(value);
      } else if (double.tryParse(value) != null) {
        props[key] = double.parse(value);
      } else {
        props[key] = value;
      }
    }

    return props;
  }

  /// 解析内联YAML格式 { key: value, key: value }
  Map<String, dynamic> _parseInlineYaml(String inline) {
    final props = <String, dynamic>{};

    // 移除花括号
    var content = inline.substring(1, inline.length - 1).trim();
    if (content.isEmpty) return props;

    // 解析键值对，处理带引号的值中的逗号
    int i = 0;
    while (i < content.length) {
      // 跳过空格
      while (i < content.length && content[i] == ' ') {
        i++;
      }
      if (i >= content.length) break;

      // 找到键
      final colonIndex = content.indexOf(':', i);
      if (colonIndex == -1) break;

      final key = content.substring(i, colonIndex).trim();
      i = colonIndex + 1;

      // 跳过冒号后的空格
      while (i < content.length && content[i] == ' ') {
        i++;
      }
      if (i >= content.length) break;

      // 解析值
      String value;
      if (content[i] == "'" || content[i] == '"') {
        // 带引号的值
        final quote = content[i];
        i++;
        final endQuote = content.indexOf(quote, i);
        if (endQuote == -1) break;
        value = content.substring(i, endQuote);
        i = endQuote + 1;
      } else {
        // 无引号的值，找到下一个逗号或结尾
        final nextComma = content.indexOf(',', i);
        if (nextComma == -1) {
          value = content.substring(i).trim();
          i = content.length;
        } else {
          value = content.substring(i, nextComma).trim();
          i = nextComma;
        }
      }

      // 跳过逗号
      if (i < content.length && content[i] == ',') {
        i++;
      }

      // 存储值
      if (value == 'true') {
        props[key] = true;
      } else if (value == 'false') {
        props[key] = false;
      } else if (int.tryParse(value) != null) {
        props[key] = int.parse(value);
      } else if (double.tryParse(value) != null) {
        props[key] = double.parse(value);
      } else {
        props[key] = value;
      }
    }

    return props;
  }

  /// 解析 SIP008 JSON 格式
  List<ProxyNode> _parseSip008(String content) {
    final nodes = <ProxyNode>[];

    try {
      final json = jsonDecode(content);

      List<dynamic> servers;
      if (json is List) {
        servers = json;
      } else if (json is Map && json['servers'] != null) {
        servers = json['servers'] as List;
      } else {
        return nodes;
      }

      for (final server in servers) {
        if (server is! Map) continue;

        final node = ProxyNode(
          id:
              server['id']?.toString() ??
              '${server['server']}_${server['server_port']}',
          name:
              server['remarks'] as String? ?? server['server'] as String? ?? '',
          server: server['server'] as String? ?? '',
          port: server['server_port'] as int? ?? 0,
          protocol: ProtocolType.shadowsocks,
          settings: {
            'method': server['method'],
            'password': server['password'],
            'plugin': server['plugin'],
            'plugin_opts': server['plugin_opts'],
          },
        );

        if (node.server.isNotEmpty && node.port > 0) {
          nodes.add(node);
        }
      }

      VortexLogger.i('Parsed ${nodes.length} nodes from SIP008');
    } catch (e) {
      VortexLogger.e('Failed to parse SIP008', e);
    }

    return nodes;
  }

  /// 解析 Base64 解码后的内容
  List<ProxyNode> _parseBase64Content(String content) {
    // Base64 解码后通常是 URI 列表
    return _parseUriList(content);
  }

  /// 解析 URI 列表格式
  List<ProxyNode> _parseUriList(String content) {
    final nodes = <ProxyNode>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final uri = line.trim();
      if (uri.isEmpty) continue;

      final node = _parseProxyUri(uri);
      if (node != null) {
        nodes.add(node);
      }
    }

    VortexLogger.i('Parsed ${nodes.length} nodes from URI list');
    return nodes;
  }

  /// 解析代理 URI
  ProxyNode? _parseProxyUri(String uri) {
    try {
      if (uri.startsWith('ss://')) {
        return _parseShadowsocksUri(uri);
      } else if (uri.startsWith('ssr://')) {
        return _parseShadowsocksRUri(uri);
      } else if (uri.startsWith('vmess://')) {
        return _parseVmessUri(uri);
      } else if (uri.startsWith('vless://')) {
        return _parseVlessUri(uri);
      } else if (uri.startsWith('trojan://')) {
        return _parseTrojanUri(uri);
      } else if (uri.startsWith('hysteria://')) {
        return _parseHysteriaUri(uri);
      } else if (uri.startsWith('hysteria2://') || uri.startsWith('hy2://')) {
        return _parseHysteria2Uri(uri);
      } else if (uri.startsWith('tuic://')) {
        return _parseTuicUri(uri);
      }
    } catch (e) {
      VortexLogger.w('Failed to parse URI: $uri - $e');
    }
    return null;
  }

  /// 解析 Shadowsocks URI
  ProxyNode? _parseShadowsocksUri(String uri) {
    // ss://BASE64(method:password)@server:port#name
    // ss://BASE64(method:password@server:port)#name
    try {
      final withoutScheme = uri.substring(5);
      String? name;
      String mainPart;

      final hashIndex = withoutScheme.lastIndexOf('#');
      if (hashIndex != -1) {
        name = Uri.decodeComponent(withoutScheme.substring(hashIndex + 1));
        mainPart = withoutScheme.substring(0, hashIndex);
      } else {
        mainPart = withoutScheme;
      }

      String method, password, server;
      int port;

      if (mainPart.contains('@')) {
        // 新格式: BASE64(method:password)@server:port
        final atIndex = mainPart.lastIndexOf('@');
        final userInfo = utf8.decode(
          base64.decode(_addBase64Padding(mainPart.substring(0, atIndex))),
        );
        final serverInfo = mainPart.substring(atIndex + 1);

        final colonIndex = userInfo.indexOf(':');
        method = userInfo.substring(0, colonIndex);
        password = userInfo.substring(colonIndex + 1);

        final serverColonIndex = serverInfo.lastIndexOf(':');
        server = serverInfo.substring(0, serverColonIndex);
        port = int.parse(serverInfo.substring(serverColonIndex + 1));
      } else {
        // 旧格式: BASE64(method:password@server:port)
        final decoded = utf8.decode(base64.decode(_addBase64Padding(mainPart)));
        final atIndex = decoded.lastIndexOf('@');
        final userInfo = decoded.substring(0, atIndex);
        final serverInfo = decoded.substring(atIndex + 1);

        final colonIndex = userInfo.indexOf(':');
        method = userInfo.substring(0, colonIndex);
        password = userInfo.substring(colonIndex + 1);

        final serverColonIndex = serverInfo.lastIndexOf(':');
        server = serverInfo.substring(0, serverColonIndex);
        port = int.parse(serverInfo.substring(serverColonIndex + 1));
      }

      return ProxyNode(
        id: '${server}_$port',
        name: name ?? server,
        server: server,
        port: port,
        protocol: ProtocolType.shadowsocks,
        settings: {'method': method, 'password': password},
        tags: _extractTags(name ?? ''),
        multiplier: _extractMultiplier(name ?? ''),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse SS URI: $e');
      return null;
    }
  }

  /// 解析 ShadowsocksR URI
  ProxyNode? _parseShadowsocksRUri(String uri) {
    try {
      final withoutScheme = uri.substring(6);
      final decoded = utf8.decode(
        base64.decode(_addBase64Padding(withoutScheme)),
      );

      // server:port:protocol:method:obfs:base64(password)/?params
      final parts = decoded.split('/?');
      final mainParts = parts[0].split(':');

      if (mainParts.length < 6) return null;

      final server = mainParts[0];
      final port = int.parse(mainParts[1]);
      final protocol = mainParts[2];
      final method = mainParts[3];
      final obfs = mainParts[4];
      final password = utf8.decode(
        base64.decode(_addBase64Padding(mainParts[5])),
      );

      String? name;
      String? obfsParam;
      String? protocolParam;

      if (parts.length > 1) {
        final params = Uri.splitQueryString(parts[1]);
        if (params['remarks'] != null) {
          name = utf8.decode(
            base64.decode(_addBase64Padding(params['remarks']!)),
          );
        }
        if (params['obfsparam'] != null) {
          obfsParam = utf8.decode(
            base64.decode(_addBase64Padding(params['obfsparam']!)),
          );
        }
        if (params['protoparam'] != null) {
          protocolParam = utf8.decode(
            base64.decode(_addBase64Padding(params['protoparam']!)),
          );
        }
      }

      return ProxyNode(
        id: '${server}_$port',
        name: name ?? server,
        server: server,
        port: port,
        protocol: ProtocolType.shadowsocksR,
        settings: {
          'method': method,
          'password': password,
          'protocol': protocol,
          'protocol_param': protocolParam,
          'obfs': obfs,
          'obfs_param': obfsParam,
        },
        tags: _extractTags(name ?? ''),
        multiplier: _extractMultiplier(name ?? ''),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse SSR URI: $e');
      return null;
    }
  }

  /// 解析 VMess URI
  ProxyNode? _parseVmessUri(String uri) {
    try {
      final withoutScheme = uri.substring(8);
      final decoded = utf8.decode(
        base64.decode(_addBase64Padding(withoutScheme)),
      );
      final json = jsonDecode(decoded) as Map<String, dynamic>;

      final server = json['add'] as String? ?? '';
      final port = _parseInt(json['port']) ?? 0;
      final name =
          json['ps'] as String? ?? json['remarks'] as String? ?? server;

      return ProxyNode(
        id: '${server}_$port',
        name: name,
        server: server,
        port: port,
        protocol: ProtocolType.vmess,
        settings: {
          'uuid': json['id'],
          'alter_id': _parseInt(json['aid']) ?? 0,
          'cipher': json['scy'] ?? json['security'] ?? 'auto',
          'network': json['net'] ?? 'tcp',
          'tls': json['tls'] == 'tls',
          'sni': json['sni'] ?? json['host'],
          'ws_path': json['path'],
          'ws_host': json['host'],
        },
        tags: _extractTags(name),
        multiplier: _extractMultiplier(name),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse VMess URI: $e');
      return null;
    }
  }

  /// 解析 VLESS URI
  ProxyNode? _parseVlessUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      final server = parsed.host;
      final port = parsed.port;
      final uuid = parsed.userInfo;
      final name = parsed.fragment.isNotEmpty
          ? Uri.decodeComponent(parsed.fragment)
          : server;

      final params = parsed.queryParameters;

      return ProxyNode(
        id: '${server}_$port',
        name: name,
        server: server,
        port: port,
        protocol: ProtocolType.vless,
        settings: {
          'uuid': uuid,
          'flow': params['flow'],
          'encryption': params['encryption'] ?? 'none',
          'network': params['type'] ?? 'tcp',
          'security': params['security'] ?? 'none',
          'sni': params['sni'],
          'fp': params['fp'],
          'pbk': params['pbk'],
          'sid': params['sid'],
          'path': params['path'],
          'host': params['host'],
        },
        tags: _extractTags(name),
        multiplier: _extractMultiplier(name),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse VLESS URI: $e');
      return null;
    }
  }

  /// 解析 Trojan URI
  ProxyNode? _parseTrojanUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      final server = parsed.host;
      final port = parsed.port;
      final password = parsed.userInfo;
      final name = parsed.fragment.isNotEmpty
          ? Uri.decodeComponent(parsed.fragment)
          : server;

      final params = parsed.queryParameters;

      return ProxyNode(
        id: '${server}_$port',
        name: name,
        server: server,
        port: port,
        protocol: ProtocolType.trojan,
        settings: {
          'password': password,
          'sni': params['sni'] ?? params['peer'],
          'skip_cert_verify': params['allowInsecure'] == '1',
          'network': params['type'] ?? 'tcp',
          'path': params['path'],
          'host': params['host'],
        },
        tags: _extractTags(name),
        multiplier: _extractMultiplier(name),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse Trojan URI: $e');
      return null;
    }
  }

  /// 解析 Hysteria URI
  ProxyNode? _parseHysteriaUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      final server = parsed.host;
      final port = parsed.port;
      final name = parsed.fragment.isNotEmpty
          ? Uri.decodeComponent(parsed.fragment)
          : server;

      final params = parsed.queryParameters;

      return ProxyNode(
        id: '${server}_$port',
        name: name,
        server: server,
        port: port,
        protocol: ProtocolType.hysteria,
        settings: {
          'auth': params['auth'],
          'auth_str': params['auth_str'],
          'obfs': params['obfs'],
          'alpn': params['alpn'],
          'protocol': params['protocol'] ?? 'udp',
          'up': params['upmbps'],
          'down': params['downmbps'],
          'sni': params['peer'] ?? params['sni'],
          'skip_cert_verify': params['insecure'] == '1',
        },
        tags: _extractTags(name),
        multiplier: _extractMultiplier(name),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse Hysteria URI: $e');
      return null;
    }
  }

  /// 解析 Hysteria2 URI
  ProxyNode? _parseHysteria2Uri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      final server = parsed.host;
      final port = parsed.port;
      final password = parsed.userInfo;
      final name = parsed.fragment.isNotEmpty
          ? Uri.decodeComponent(parsed.fragment)
          : server;

      final params = parsed.queryParameters;

      return ProxyNode(
        id: '${server}_$port',
        name: name,
        server: server,
        port: port,
        protocol: ProtocolType.hysteria2,
        settings: {
          'password': password,
          'obfs': params['obfs'],
          'obfs_password': params['obfs-password'],
          'sni': params['sni'],
          'skip_cert_verify': params['insecure'] == '1',
        },
        tags: _extractTags(name),
        multiplier: _extractMultiplier(name),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse Hysteria2 URI: $e');
      return null;
    }
  }

  /// 解析 TUIC URI
  ProxyNode? _parseTuicUri(String uri) {
    try {
      final parsed = Uri.parse(uri);
      final server = parsed.host;
      final port = parsed.port;
      final userInfo = parsed.userInfo.split(':');
      final uuid = userInfo.isNotEmpty ? userInfo[0] : '';
      final password = userInfo.length > 1 ? userInfo[1] : '';
      final name = parsed.fragment.isNotEmpty
          ? Uri.decodeComponent(parsed.fragment)
          : server;

      final params = parsed.queryParameters;

      return ProxyNode(
        id: '${server}_$port',
        name: name,
        server: server,
        port: port,
        protocol: ProtocolType.tuic,
        settings: {
          'uuid': uuid,
          'password': password,
          'congestion_control': params['congestion_control'] ?? 'bbr',
          'alpn': params['alpn']?.split(','),
          'sni': params['sni'],
          'skip_cert_verify': params['insecure'] == '1',
          'udp_relay_mode': params['udp_relay_mode'],
        },
        tags: _extractTags(name),
        multiplier: _extractMultiplier(name),
      );
    } catch (e) {
      VortexLogger.w('Failed to parse TUIC URI: $e');
      return null;
    }
  }

  // ==================== Helper Methods ====================

  String _addBase64Padding(String input) {
    final remainder = input.length % 4;
    if (remainder == 0) return input;
    return input + '=' * (4 - remainder);
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  ProtocolType? _getProtocolType(String type) {
    switch (type.toLowerCase()) {
      case 'ss':
      case 'shadowsocks':
        return ProtocolType.shadowsocks;
      case 'ssr':
      case 'shadowsocksr':
        return ProtocolType.shadowsocksR;
      case 'vmess':
        return ProtocolType.vmess;
      case 'vless':
        return ProtocolType.vless;
      case 'trojan':
        return ProtocolType.trojan;
      case 'hysteria':
        return ProtocolType.hysteria;
      case 'hysteria2':
        return ProtocolType.hysteria2;
      case 'tuic':
        return ProtocolType.tuic;
      case 'wireguard':
      case 'wg':
        return ProtocolType.wireguard;
      case 'anytls':
        return ProtocolType.anytls;
      default:
        return null;
    }
  }

  List<NodeTag> _extractTags(String name) {
    final tags = <NodeTag>[];
    final lowerName = name.toLowerCase();

    if (lowerName.contains('解锁') || lowerName.contains('unlock')) {
      tags.add(NodeTag.unlock);
    }
    if (lowerName.contains('游戏') || lowerName.contains('game')) {
      tags.add(NodeTag.gaming);
    }
    if (lowerName.contains('流媒体') || lowerName.contains('stream')) {
      tags.add(NodeTag.streaming);
    }
    if (lowerName.contains('chatgpt') ||
        lowerName.contains('gpt') ||
        lowerName.contains('openai')) {
      tags.add(NodeTag.chatgpt);
    }
    if (lowerName.contains('netflix') || lowerName.contains('nf')) {
      tags.add(NodeTag.netflix);
    }
    if (lowerName.contains('disney') || lowerName.contains('d+')) {
      tags.add(NodeTag.disney);
    }

    return tags;
  }

  double _extractMultiplier(String name) {
    final regex = RegExp(r'(\d+\.?\d*)\s*[xX倍]');
    final match = regex.firstMatch(name);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 1.0;
    }
    return 1.0;
  }
}
