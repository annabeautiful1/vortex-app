# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 📋 开发进度追踪

### ✅ 已完成功能

#### 阶段一：项目基础架构
- [x] Flutter 跨平台项目创建（iOS/Android/macOS/Windows）
- [x] GitHub 仓库配置和 CI/CD 工作流
- [x] 基础目录结构和代码规范
- [x] Riverpod 状态管理架构
- [x] GoRouter 导航系统
- [x] 主题系统（亮色/暗色）

#### 阶段二：核心服务层
- [x] `PlatformChannelService` - Flutter ↔ 原生通信
- [x] `MihomoService` - Clash.Meta REST API 客户端
- [x] `VpnService` - VPN 连接生命周期管理
- [x] `ApiManager` - 多 API 轮询和故障转移
- [x] `StorageService` - 本地存储（Hive + SecureStorage）
- [x] `SubscriptionParser` - 订阅解析器（支持 Clash YAML、Base64、SIP008、URI 列表）

#### 阶段三：平台原生代码
- [x] Windows: Platform Channel + 系统代理设置 + Mihomo 核心管理
- [x] macOS: Platform Channel 基础实现
- [x] iOS: Platform Channel 基础实现
- [x] Android: Platform Channel 基础实现

#### 阶段四：UI 界面
- [x] Dashboard 页面布局
- [x] 连接按钮（动画效果）
- [x] 状态卡片（连接状态/延迟/协议）
- [x] 实时流量卡片（上传/下载速度）
- [x] 套餐流量卡片（已用/总量）
- [x] 节点列表页面框架
- [x] 设置页面框架
- [x] 登录页面框架
- [x] 系统托盘（TrayService）

#### 阶段五：VPN 连接管理
- [x] `ConnectionProvider` 状态管理
- [x] 连接/断开/切换节点逻辑
- [x] 流量统计 StreamProvider
- [x] Mihomo 配置文件生成
- [x] 后台核心预启动（避免测速卡顿）
- [x] 静默模式（测速时不影响 UI 状态）

#### 阶段六：用户认证系统
- [x] SSPanel 登录/注册 API 对接
- [x] V2board 登录/注册 API 对接
- [x] Token 存储和自动刷新
- [x] 自动登录功能（启动时检查保存的会话）
- [x] 凭据保存和自动重登录

#### 阶段七：订阅管理
- [x] 从面板获取订阅链接
- [x] 解析 Clash/ClashMeta 格式
- [x] 节点列表更新
- [x] 登录成功后自动获取节点列表
- [x] 支持多种订阅类型参数（clashmeta/meta/1-4）

---

## 🔄 与成熟客户端的对比分析

### 参考客户端
- **Clash for Windows** (已停止维护) - Electron + Go Core
- **Clash Verge Rev** - Tauri (Rust) + React + Mihomo
- **FlClash** - Flutter + Mihomo (与我们技术栈相同，26.6k+ stars)

### FlClash 架构参考（Flutter 同技术栈）

FlClash 的架构对我们最有参考价值，因为技术栈完全相同：

```
┌─────────────────────────────────────────────────┐
│           Flutter UI Layer (Dart)               │
│  ┌──────────┬──────────┬──────────┬──────────┐ │
│  │  Pages   │  Widgets │  Views   │  Common  │ │
│  └──────────┴──────────┴──────────┴──────────┘ │
└─────────────────────────────────────────────────┘
                      ↕ (Riverpod State Management)
┌─────────────────────────────────────────────────┐
│        Application Logic Layer (Dart)           │
│  ┌──────────┬──────────┬──────────┬──────────┐ │
│  │Providers │Controller│ Managers │  Models  │ │
│  └──────────┴──────────┴──────────┴──────────┘ │
└─────────────────────────────────────────────────┘
                      ↕ (FFI / Platform Channel)
┌─────────────────────────────────────────────────┐
│         Native Platform Layer                   │
│  ┌──────────┬──────────┬──────────┬──────────┐ │
│  │ Android  │ Windows  │  macOS   │  Linux   │ │
│  │(Kotlin)  │  (C++)   │  (C++)   │  (C++)   │ │
│  └──────────┴──────────┴──────────┴──────────┘ │
└─────────────────────────────────────────────────┘
                      ↕ (C Bridge / CGO)
┌─────────────────────────────────────────────────┐
│          Go Core Layer (ClashMeta)              │
│  ┌──────────┬──────────┬──────────┬──────────┐ │
│  │  Action  │  Bridge  │   Hub    │   TUN    │ │
│  │ Dispatch │   FFI    │  Events  │  Network │ │
│  └──────────┴──────────┴──────────┴──────────┘ │
└─────────────────────────────────────────────────┘
```

**FlClash 关键设计**：
- **核心集成**: ClashMeta 作为 Git Submodule，编译为动态库 (libclash.so/dll)
- **通信方式**: FFI 直接调用 Go 导出函数，事件通过回调返回
- **Manager 模式**: 13 个 Manager 管理不同功能模块
- **TUN 实现**: Android 使用 VpnService + gVisor 网络栈

### 架构对比

| 功能模块 | Clash Verge Rev | Vortex (我们) | 差距分析 |
|---------|----------------|---------------|---------|
| 核心管理 | Sidecar + Service 双模式 | 仅 Sidecar 模式 | 需要添加 Service 模式支持 TUN |
| 配置验证 | Draft-Validate-Apply | 直接应用 | 需要添加配置验证机制 |
| 配置增强 | Merge + Script 管道 | 无 | 可选功能 |
| 延迟测试 | HTTPS URL + unified-delay | 已实现 | ✅ 已对齐 |
| 系统代理 | sysproxy-rs + 代理守护 | 基础实现 | 需要添加代理守护 |
| TUN 模式 | Service 模式支持 | 配置已有，实现待完善 | 需要完善各平台实现 |
| 连接管理 | WebSocket 实时流 | REST API 轮询 | 可优化为 WebSocket |
| 日志系统 | 分级 + 自动清理 + 流传输 | 基础日志 | 需要完善 |
| 配置文件 | 多配置 + 激活切换 | 单配置 | 可选功能 |

---

## 🚧 待完成功能（按优先级排序）

### 🔴 高优先级（核心代理功能）

#### 1. 配置验证机制（参考 Clash Verge Rev）
- [ ] 实现 `mihomo -t -f config.yaml` 配置验证
- [ ] 验证失败自动回滚
- [ ] 配置错误提示

#### 2. 代理守护（Proxy Guard）
- [ ] 监控系统代理设置是否被外部修改
- [ ] 自动检测和恢复代理设置
- [ ] 可配置检查间隔

#### 3. 核心管理优化
- [ ] Windows: 将核心启动移到后台线程（避免 UI 阻塞）
- [ ] 添加核心健康检查定时器
- [ ] 核心崩溃自动重启

#### 4. TUN 模式完善
- [ ] Windows: 实现 TUN 模式（需要管理员权限）
- [ ] macOS: 实现 TUN 模式（Network Extension）
- [ ] Android: VpnService 实现
- [ ] iOS: Network Extension 实现

#### 5. 连接管理优化
- [ ] WebSocket 实时连接监控（替代 REST 轮询）
- [ ] 连接列表虚拟化渲染（大量连接时）
- [ ] 关闭指定连接功能

### 🟡 中优先级（用户体验）

#### 6. 节点管理增强
- [ ] 节点分组展示
- [ ] 节点标签筛选（解锁、游戏、流媒体等）
- [ ] 倍率标签显示
- [ ] 节点排序（按延迟、按名称）
- [ ] 节点搜索

#### 7. 日志系统完善
- [ ] 日志分级（debug/info/warning/error）
- [ ] 日志自动清理（1天/7天/30天）
- [ ] 日志实时流传输到 UI
- [ ] 日志导出功能

#### 8. 设置功能完善
- [ ] 开机自启动（各平台实现）
- [ ] 自动连接（启动时自动连接上次节点）
- [ ] 代理模式切换（系统代理/TUN/直连）
- [ ] 允许局域网访问

#### 9. 代理组支持
- [ ] 代理组展示（Select/URL-Test/Fallback/Load-Balance）
- [ ] 代理组节点切换
- [ ] 自动选择最低延迟节点

### 🟢 低优先级（增值功能）

#### 10. 配置增强管道（可选）
- [ ] Merge 配置支持（YAML 合并）
- [ ] Script 配置支持（JavaScript 转换）
- [ ] 多配置管理和切换

#### 11. 规则管理
- [ ] 规则列表展示
- [ ] 自定义规则添加
- [ ] Rule Provider 支持

#### 12. 其他功能
- [ ] 公告系统 - 从面板获取公告
- [ ] 客服系统 - Crisp/Telegram 消息对接
- [ ] 内购系统 - 续费引导
- [ ] 自定义主题 - Logo/名称/颜色
- [ ] 多语言支持

---

## 🎯 技术优化建议

### 1. 核心启动优化（解决 UI 卡顿）

**问题**：Windows 原生代码中 `startCore()` 有 `Sleep(500)` 阻塞主线程

**解决方案**（参考 Clash Verge Rev）：
```cpp
// 将核心启动移到后台线程
std::thread([this, configPath]() {
    // 启动核心
    bool success = StartCoreInternal(configPath);
    // 通过回调通知 Flutter
    PostStateCallback(success ? "connected" : "error");
}).detach();
```

### 2. 配置验证机制

**实现方式**：
```dart
Future<bool> validateConfig(String configPath) async {
  final result = await Process.run('mihomo', ['-t', '-f', configPath]);
  return result.exitCode == 0;
}

Future<bool> applyConfig(String configPath) async {
  // 1. 验证配置
  if (!await validateConfig(configPath)) {
    VortexLogger.e('Config validation failed');
    return false;
  }
  // 2. 应用配置
  return await _platformChannel.reloadConfig(configPath);
}
```

### 3. 代理守护实现

```dart
class ProxyGuard {
  Timer? _guardTimer;

  void start() {
    _guardTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _checkAndRestoreProxy();
    });
  }

  Future<void> _checkAndRestoreProxy() async {
    final currentProxy = await _getSystemProxy();
    if (_shouldBeEnabled && !currentProxy.enabled) {
      VortexLogger.w('System proxy was modified externally, restoring...');
      await _platformChannel.setSystemProxy(true, port: _expectedPort);
    }
  }
}
```

### 4. WebSocket 连接监控

```dart
class ConnectionMonitor {
  WebSocket? _ws;

  Future<void> connect() async {
    _ws = await WebSocket.connect('ws://127.0.0.1:9090/connections');
    _ws!.listen((data) {
      final connections = jsonDecode(data);
      _connectionController.add(connections);
    });
  }
}
```

---

## 📁 项目结构

```
lib/
├── app.dart                          # 应用入口和路由
├── main.dart                         # Flutter 入口
├── core/                             # 核心服务
│   ├── api/                          # API 客户端
│   │   ├── api_manager.dart          # 多 API 轮询管理
│   │   ├── sspanel_api.dart          # SSPanel API
│   │   └── v2board_api.dart          # V2board API
│   ├── config/                       # 配置
│   │   └── build_config.dart         # 构建配置
│   ├── platform/                     # 平台通道
│   │   └── platform_channel_service.dart
│   ├── proxy/                        # 代理服务
│   │   ├── mihomo_service.dart       # Mihomo REST API
│   │   └── proxy_core.dart           # 代理核心接口
│   ├── subscription/                 # 订阅解析
│   │   └── subscription_parser.dart
│   ├── utils/                        # 工具类
│   │   ├── logger.dart
│   │   └── dev_mode.dart
│   └── vpn/                          # VPN 服务
│       └── vpn_service.dart          # VPN 生命周期管理
├── features/                         # 功能模块
│   ├── auth/                         # 认证
│   │   ├── domain/auth_provider.dart
│   │   └── presentation/pages/login_page.dart
│   ├── dashboard/                    # 仪表盘
│   │   ├── domain/connection_provider.dart
│   │   └── presentation/
│   ├── nodes/                        # 节点管理
│   │   ├── domain/nodes_provider.dart
│   │   └── presentation/pages/nodes_page.dart
│   ├── settings/                     # 设置
│   │   └── presentation/pages/settings_page.dart
│   ├── support/                      # 客服
│   │   └── presentation/pages/support_page.dart
│   └── debug/                        # 调试
│       └── presentation/pages/debug_panel.dart
└── shared/                           # 共享组件
    ├── constants/app_constants.dart
    ├── models/                       # 数据模型
    │   ├── proxy_node.dart
    │   └── user.dart
    ├── services/                     # 共享服务
    │   ├── storage_service.dart
    │   ├── tray_service.dart
    │   ├── crisp_service.dart
    │   └── window_service.dart
    └── themes/app_theme.dart
```

---

## 🔧 Common Commands

```bash
# Install dependencies
flutter pub get

# Run development
flutter run

# Code analysis
flutter analyze

# Format code (required before commit - CI enforces this)
dart format lib/

# Run tests
flutter test

# Build releases
flutter build apk --release          # Android APK
flutter build appbundle --release    # Android AAB (Play Store)
flutter build ios --release          # iOS
flutter build macos --release        # macOS
flutter build windows --release      # Windows
```

---

## 🏗️ Architecture

### State Management
Uses Riverpod with `StateNotifier` pattern. All providers are in `domain/` folders within each feature:
- `ConnectionNotifier` → `VpnConnectionState`
- `AuthNotifier` → `AuthState`
- `NodesNotifier` → `NodesState`
- `SettingsNotifier` → `SettingsState`

### Navigation
GoRouter with a `ShellRoute` for the main navigation rail. Routes defined in `lib/app.dart`.

### Core Services (Singletons)
- `ApiManager.instance` - Multi-API polling with auto-failover
- `VpnService.instance` - VPN connection lifecycle management
- `MihomoService.instance` - REST API client for Mihomo external controller
- `StorageService.instance` - Hive + SecureStorage wrapper
- `PlatformChannelService.instance` - Flutter ↔ Native communication
- `TrayService.instance` - System tray management

### Panel API Patterns
Two panel types with different endpoints:
- **V2board**: `/api/v1/guest/comm/config` (guest), `/api/v1/user/*` (auth)
- **SSPanel**: `/guest_config.txt` (guest), custom auth endpoints

### Feature Structure
Each feature follows: `features/{name}/domain/` (providers) + `features/{name}/presentation/` (UI)

---

## 📝 Key Conventions

- Class `VpnConnectionState` is used instead of `ConnectionState` to avoid collision with Flutter's async library
- All data models use manual `copyWith()`, `toJson()`, `fromJson()` (no code generation)
- Chinese error messages in `ErrorMessages` class, English for logs
- Theme colors defined in `AppTheme` with connection status colors
- 后台核心预启动模式：应用启动时预启动 Mihomo 核心，测速时直接使用，避免卡顿
- 静默模式：测速时不广播状态变化，避免影响 UI

---

## 🔐 Mihomo REST API 接口

```
GET  /                    # 健康检查
GET  /version             # 获取版本
GET  /configs             # 获取配置
PUT  /configs             # 重载配置
GET  /proxies             # 获取所有代理
GET  /proxies/{name}      # 获取单个代理
PUT  /proxies/{name}      # 切换代理
GET  /proxies/{name}/delay # 测试延迟
GET  /rules               # 获取规则
GET  /connections         # 获取连接（支持 WebSocket）
DELETE /connections       # 关闭所有连接
DELETE /connections/{id}  # 关闭单个连接
GET  /traffic             # 流量统计（SSE）
GET  /logs                # 日志流（SSE）
GET  /memory              # 内存使用
PUT  /providers/proxies/{name}  # 刷新代理 Provider
PUT  /providers/rules/{name}    # 刷新规则 Provider
```

---

## 🚀 CI/CD

GitHub Actions runs on push to master:
- `ci.yml`: analyze, format check, test
- `build.yml`: multi-platform builds (artifacts uploaded)

Format check is strict - run `dart format lib/` before committing.

---

## 📚 参考资源

- [Clash Verge Rev GitHub](https://github.com/clash-verge-rev/clash-verge-rev)
- [FlClash GitHub](https://github.com/chen08209/FlClash)
- [Mihomo GitHub](https://github.com/MetaCubeX/mihomo)
- [Mihomo Wiki](https://wiki.metacubex.one/)
- [sysproxy-rs](https://github.com/zzzgydi/sysproxy-rs) - 系统代理设置库

---

## ⚠️ 常见问题

### 1. 登录时提示"查询后端"
表明无可用 API 或 API 全部测活失败。检查：
- V2board: `http(s)://API地址/api/v1/guest/comm/config`
- SSPanel: `http(s)://API地址/guest_config.txt`

### 2. 订阅无节点或只有 DIRECT/REJECT
- 检查订阅链接的国内连接性
- 检查是否有不支持的字段（如 GEOSITE）
- 配置文件过大时使用 rule-provider

### 3. 断电后无法上网
系统代理未恢复，重新打开客户端会自动修复。建议开启"开机启动"。

### 4. 核心未启动
- Windows: 杀毒软件拦截，关闭杀毒软件重装
- macOS: 其他代理软件占用端口，卸载后重启
