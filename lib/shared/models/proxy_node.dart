import 'package:freezed_annotation/freezed_annotation.dart';

part 'proxy_node.freezed.dart';
part 'proxy_node.g.dart';

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
@freezed
class ProxyNode with _$ProxyNode {
  const factory ProxyNode({
    required String id,
    required String name,
    required String server,
    required int port,
    required ProtocolType protocol,
    required Map<String, dynamic> settings,

    // Display info
    String? group,
    @Default(1.0) double multiplier, // 倍率
    @Default([]) List<NodeTag> tags,
    String? customTag,

    // Status
    @Default(false) bool isSelected,
    int? latency, // TCP latency in ms
    DateTime? lastTested,
  }) = _ProxyNode;

  factory ProxyNode.fromJson(Map<String, dynamic> json) =>
      _$ProxyNodeFromJson(json);
}

/// Shadowsocks settings
@freezed
class ShadowsocksSettings with _$ShadowsocksSettings {
  const factory ShadowsocksSettings({
    required String method, // Encryption method
    required String password,
    String? plugin, // obfs, v2ray-plugin, shadow-tls, restls
    Map<String, dynamic>? pluginOpts,
    @Default(false) bool is2022, // SS-2022
    @Default(false) bool smux, // SMUX support
  }) = _ShadowsocksSettings;

  factory ShadowsocksSettings.fromJson(Map<String, dynamic> json) =>
      _$ShadowsocksSettingsFromJson(json);
}

/// VMess settings
@freezed
class VMessSettings with _$VMessSettings {
  const factory VMessSettings({
    required String uuid,
    required int alterId,
    @Default('auto') String security,
    String? network, // tcp, ws, http, h2, grpc, quic
    Map<String, dynamic>? networkSettings,
    @Default(false) bool tls,
    String? sni,
  }) = _VMessSettings;

  factory VMessSettings.fromJson(Map<String, dynamic> json) =>
      _$VMessSettingsFromJson(json);
}

/// VLESS settings
@freezed
class VLessSettings with _$VLessSettings {
  const factory VLessSettings({
    required String uuid,
    @Default('none') String flow, // xtls-rprx-vision
    String? network, // tcp, ws, grpc
    Map<String, dynamic>? networkSettings,
    @Default(false) bool tls,
    String? sni,
    String? fingerprint,
    // Reality settings
    @Default(false) bool reality,
    String? publicKey,
    String? shortId,
  }) = _VLessSettings;

  factory VLessSettings.fromJson(Map<String, dynamic> json) =>
      _$VLessSettingsFromJson(json);
}

/// Trojan settings
@freezed
class TrojanSettings with _$TrojanSettings {
  const factory TrojanSettings({
    required String password,
    String? sni,
    @Default(true) bool tls,
    @Default(false) bool skipCertVerify,
    String? network, // tcp, ws, grpc
    Map<String, dynamic>? networkSettings,
  }) = _TrojanSettings;

  factory TrojanSettings.fromJson(Map<String, dynamic> json) =>
      _$TrojanSettingsFromJson(json);
}

/// Hysteria settings
@freezed
class HysteriaSettings with _$HysteriaSettings {
  const factory HysteriaSettings({
    required String auth,
    String? obfs,
    String? alpn,
    int? upMbps,
    int? downMbps,
    String? sni,
    @Default(false) bool skipCertVerify,
    @Default(1) int version, // 1 or 2
  }) = _HysteriaSettings;

  factory HysteriaSettings.fromJson(Map<String, dynamic> json) =>
      _$HysteriaSettingsFromJson(json);
}

/// TUIC settings
@freezed
class TuicSettings with _$TuicSettings {
  const factory TuicSettings({
    required String uuid,
    required String password,
    String? congestionControl,
    String? alpn,
    String? sni,
    @Default(false) bool skipCertVerify,
    @Default(false) bool udpRelayMode,
  }) = _TuicSettings;

  factory TuicSettings.fromJson(Map<String, dynamic> json) =>
      _$TuicSettingsFromJson(json);
}

/// WireGuard settings
@freezed
class WireGuardSettings with _$WireGuardSettings {
  const factory WireGuardSettings({
    required String privateKey,
    required String publicKey,
    String? preSharedKey,
    required List<String> addresses,
    List<String>? dns,
    int? mtu,
    List<String>? allowedIps,
  }) = _WireGuardSettings;

  factory WireGuardSettings.fromJson(Map<String, dynamic> json) =>
      _$WireGuardSettingsFromJson(json);
}

/// AnyTLS settings
@freezed
class AnyTlsSettings with _$AnyTlsSettings {
  const factory AnyTlsSettings({
    required String password,
    String? sni,
    @Default(false) bool skipCertVerify,
  }) = _AnyTlsSettings;

  factory AnyTlsSettings.fromJson(Map<String, dynamic> json) =>
      _$AnyTlsSettingsFromJson(json);
}
