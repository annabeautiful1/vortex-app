/// Supported protocol types
enum ProtocolType {
  shadowsocks,
  shadowsocksR,
  vmess,
  vless,
  trojan,
  hysteria,
  hysteria2,
  tuic,
  wireguard,
  anytls,
}

/// Node tag types for display
enum NodeTag {
  unlock,      // 解锁
  gaming,      // 游戏
  streaming,   // 流媒体
  chatgpt,     // ChatGPT
  netflix,     // Netflix
  disney,      // Disney+
  custom,      // 自定义
}

/// Proxy node model
class ProxyNode {
  final String id;
  final String name;
  final String server;
  final int port;
  final ProtocolType protocol;
  final Map<String, dynamic> settings;
  final String? group;
  final double multiplier;
  final List<NodeTag> tags;
  final String? customTag;
  final bool isSelected;
  final int? latency;
  final DateTime? lastTested;

  const ProxyNode({
    required this.id,
    required this.name,
    required this.server,
    required this.port,
    required this.protocol,
    required this.settings,
    this.group,
    this.multiplier = 1.0,
    this.tags = const [],
    this.customTag,
    this.isSelected = false,
    this.latency,
    this.lastTested,
  });

  ProxyNode copyWith({
    String? id,
    String? name,
    String? server,
    int? port,
    ProtocolType? protocol,
    Map<String, dynamic>? settings,
    String? group,
    double? multiplier,
    List<NodeTag>? tags,
    String? customTag,
    bool? isSelected,
    int? latency,
    DateTime? lastTested,
  }) {
    return ProxyNode(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      port: port ?? this.port,
      protocol: protocol ?? this.protocol,
      settings: settings ?? this.settings,
      group: group ?? this.group,
      multiplier: multiplier ?? this.multiplier,
      tags: tags ?? this.tags,
      customTag: customTag ?? this.customTag,
      isSelected: isSelected ?? this.isSelected,
      latency: latency ?? this.latency,
      lastTested: lastTested ?? this.lastTested,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'server': server,
    'port': port,
    'protocol': protocol.name,
    'settings': settings,
    'group': group,
    'multiplier': multiplier,
    'tags': tags.map((t) => t.name).toList(),
    'customTag': customTag,
    'isSelected': isSelected,
    'latency': latency,
    'lastTested': lastTested?.toIso8601String(),
  };

  factory ProxyNode.fromJson(Map<String, dynamic> json) => ProxyNode(
    id: json['id'] as String,
    name: json['name'] as String,
    server: json['server'] as String,
    port: json['port'] as int,
    protocol: ProtocolType.values.firstWhere(
      (e) => e.name == json['protocol'],
      orElse: () => ProtocolType.shadowsocks,
    ),
    settings: Map<String, dynamic>.from(json['settings'] as Map? ?? {}),
    group: json['group'] as String?,
    multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
    tags: (json['tags'] as List?)
        ?.map((t) => NodeTag.values.firstWhere(
              (e) => e.name == t,
              orElse: () => NodeTag.custom,
            ))
        .toList() ?? [],
    customTag: json['customTag'] as String?,
    isSelected: json['isSelected'] as bool? ?? false,
    latency: json['latency'] as int?,
    lastTested: json['lastTested'] != null
        ? DateTime.parse(json['lastTested'] as String)
        : null,
  );
}
