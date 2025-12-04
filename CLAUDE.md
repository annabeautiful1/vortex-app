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
- [x] `SubscriptionParser` - 订阅解析器

#### 阶段三：平台原生代码
- [x] Windows: Platform Channel + 系统代理设置
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

#### 阶段五：VPN 连接管理
- [x] `ConnectionProvider` 状态管理
- [x] 连接/断开/切换节点逻辑
- [x] 流量统计 StreamProvider
- [x] Mihomo 配置文件生成

---

### 🚧 待完成功能

#### 高优先级（核心功能）
- [ ] **Mihomo 核心集成** - 嵌入 mihomo 二进制文件
  - [ ] Windows: mihomo.exe 打包和启动
  - [ ] macOS: mihomo 二进制打包
  - [ ] iOS: Network Extension 实现
  - [ ] Android: VpnService 实现
- [ ] **用户认证系统**
  - [ ] SSPanel 登录/注册 API 对接
  - [ ] V2board 登录/注册 API 对接
  - [ ] Token 存储和自动刷新
- [ ] **订阅拉取和解析**
  - [ ] 从面板获取订阅链接
  - [ ] 解析 Clash/ClashMeta 格式
  - [ ] 节点列表更新

#### 中优先级（用户体验）
- [ ] **节点管理**
  - [ ] 节点列表展示（分组/标签）
  - [ ] 节点延迟测试
  - [ ] 节点排序和筛选
  - [ ] 倍率标签显示
- [ ] **TUN 模式**
  - [ ] 各平台 TUN 实现
  - [ ] 权限请求处理
- [ ] **设置功能**
  - [ ] 开机自启动
  - [ ] 自动连接
  - [ ] 代理模式切换
  - [ ] 日志导出

#### 低优先级（增值功能）
- [ ] **公告系统** - 从面板获取公告
- [ ] **客服系统** - Telegram 消息对接
- [ ] **内购系统** - 续费引导
- [ ] **自定义主题** - Logo/名称/颜色
- [ ] **多语言支持**

---

### 🎯 下一步建议

**推荐下一步：Mihomo 核心集成（Windows 优先）**

因为 Windows 最容易调试，建议先完成：
1. 下载 mihomo Windows 二进制
2. 实现核心启动/停止逻辑
3. 测试基本代理功能
4. 验证系统代理设置生效

---

## Project Overview

Vortex (漩涡) is a cross-platform VPN client built with Flutter, supporting iOS, Android, macOS, and Windows. It uses Mihomo (Clash.Meta) as the proxy core and supports SSPanel and V2board panels.

## Common Commands

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

## Architecture

### State Management
Uses Riverpod with `StateNotifier` pattern. All providers are in `domain/` folders within each feature:
- `ConnectionNotifier` → `VpnConnectionState` (renamed to avoid Flutter's built-in `ConnectionState`)
- `AuthNotifier` → `AuthState`
- `NodesNotifier` → `NodesState`

### Navigation
GoRouter with a `ShellRoute` for the main navigation rail. Routes defined in `lib/app.dart`.

### Core Services (Singletons)
- `ApiManager.instance` - Multi-API polling with auto-failover
- `ProxyCore.instance` - Proxy core interface (FFI hooks for Mihomo)
- `MihomoService` - REST API client for Clash.Meta external controller
- `StorageService.instance` - Hive + SecureStorage wrapper
- `PlatformChannelService` - Flutter ↔ Native communication

### Panel API Patterns
Two panel types with different endpoints:
- **V2board**: `/api/v1/guest/comm/config` (guest), `/api/v1/user/*` (auth)
- **SSPanel**: `/guest_config.txt` (guest), custom auth endpoints

### Feature Structure
Each feature follows: `features/{name}/domain/` (providers) + `features/{name}/presentation/` (UI)

## Key Conventions

- Class `VpnConnectionState` is used instead of `ConnectionState` to avoid collision with Flutter's async library
- All data models use manual `copyWith()`, `toJson()`, `fromJson()` (no code generation)
- Chinese error messages in `ErrorMessages` class, English for logs
- Theme colors defined in `AppTheme` with connection status colors

## CI/CD

GitHub Actions runs on push to master:
- `ci.yml`: analyze, format check, test
- `build.yml`: multi-platform builds (artifacts uploaded)

Format check is strict - run `dart format lib/` before committing.

我需要你帮我设计一个完美，现代化，可扩展的架构，目的是为了开发一款可以运行于多种设备：IOS,MACOS,安卓,Windows，名称为：Vortex 漩涡客户端。尽量满足一套代码，只需要微调代码即可在不同的系统中稳定运行！请你首先创建项目文件夹。创建github仓库，要配置完美的github工作流，通过github在线编译，准确判断，不要出现大量编译报错的情况，并且每新增一个功能就要推送到github仓库中。
功能与特点：一键登录、一键连接，支持注册   全平台一键 TUN 模式，代理全部流量   内建代理用于 API 通信，解决阻断、反诈、直连不畅等问题  多 OSS/API 支持，自动轮询，永不被墙   全协议支持，策略组分流支持   简化 Dashboard，小白也能看懂的信息面板   可自定义主题色彩、Logo、名称、欢迎图   完善的内购系统，带续费引导，支持码类支付和跳转支付   独家一键客服系统，支持多席位，支持查看用户套餐信息，可 Telegram 消息处理，即时聊天、互发图片   优化节点延迟算法，真实反映用户端到落地的 TCP 延迟   公告支持，节点倍率标签，自定义标签（如解锁等）,安卓自定义包名。
支持sspanel-cool(/root/bbxy/baibianxiaoying.top)和v2board(/root/v2b),
支持的协议类型:Shadowsocks(SS-2022、SMUX、插件支持obfs/v2ray-plugin/shadow-tls/restls),ShadowsocksR,VMESS,VLESS(WS-TLS、TCP-TLS、reality-grpc、reality-vision、xtls-rprx-vision),Trojan,Hysteria,TUIC,WireGuard,AnyTLS.）
SSPanel面板必须部署SSPanel已部署guest_config接口（必要），否则无法对 API 进行有效性检测！我是这样部署的：在网站根目录 /public 添加 guest_config.txt 文件，内容如下：


Copy
{
	"is_email_verify": true,
	"is_invite_force": false,
	"email_whitelist_suffix": [
		"gmail.com",
		"outlook.com"
	],
	"app_description": "欢迎使用xxxx"
}

"is_email_verify" 为是否开启邮箱验证，false 为不开启，true 为开启 "is_invite_force" 为是否开启强制邀请，false 为不开启，true 为开启 "email_whitelist_suffix" 为邮箱后缀白名单，请按格式填写。"email_whitelist_suffix": null #不限制邮箱后缀，"app_description" 为客户端登陆界面左下角机场名称下的简介，可随意自定义。
V2board 订阅下发：Vortex 漩涡客户端默认采用 Clash 获取订阅配置，即节点和策略组分流规则。而 V2board 官方的 Clash.php 并不支持下发最新的协议，如 SS-2022 等。

于是，Vortex 提供了在打包时提供了订阅类型的自定义选项：可直接在订阅类型处填写 clashmeta 或者 meta，用于获取新协议的节点，如 SS-2022、Hysteria 等

V2board 版本为 1.7.1 - 1.7.3 时，请使用 clashmeta

V2board 版本为 1.7.4 时，请使用 meta。
SSPanel 订阅下发：同理，SSPanel 可自定义 1、2、3、4 ，效果等同于clash=1、2、3、4

请注意仅填写 1、2、3、4 等，不要填写 clash=1 ，会造成无法登录的问题。
客户端日志查看：客户端需要有 API 和订阅日志，方便排查问题：
1、Windows：前往 C:\Users\Administrator\.config\com.vortex.helper  ，注意修改用户名
2、macOS：打开 Finder， 键盘同时按住 Shift+Command+G，在弹出的输入框中输入 /Users/[用户名]/.config/com.vortex.helper
3、安卓：无法登录的，长按登陆界面的 Logo 两秒，日志将会复制到剪贴板；

可正常登陆的，前往 关于（About） 页面，点击导出日志即可

设置一些提示来应对常见问题：
1、登陆时提示查询后端：
如果遇到“查询有效后端”的问题，表明无可用 API 或 API 全部测活失败。此时可先查看对应客户端的日志排查问题。或者检查打包后台和 OSS 内的 API 地址测活是否正常，V2board 为 http(s)://API地址/api/v1/guest/comm/config，SSPanel 和 WHMCS 为 http(s)://API地址/guest_config.txt，若返回下图所示字段，则表明API能通过客户端测活
2、拉取订阅问题：
如果遇到订阅无法正常拉取或无节点或只有 DIRECT、REJECT 两个节点，则表明无法下载规则或下发的配置规则有问题或者配置文件过大。

对于无法正常下载规则，可检查订阅链接的国内连接性；

对于配置问题，可检查是否有 Vortex 客户端不支持的字段，如 GEOSITE 等；

对于配置文件过大——表现为几万甚至数十万条规则数的，建议使用 rule-provider 规则集的方式。
3、可能存在的无法上网问题：
如遇到电脑直接断电关机等，重启后无法连接网络的，可检查系统代理是否已被恢复，或者再打开 Vortex 客户端，会自动修复系统代理，同时建议勾选“开机启动”避免可能的网络无法连接的问题。
4、登录提示“请等待”或者左下角简介未加载
首先排除API问题，若API正常，则表明核心未启动：

macOS 核心未启动：其他软件，如 surge/clashx 等后台占用，解决方法卸载其他同类软件重启电脑。另mac请注意区分 Intel 和 m 芯片，也会导致核心不启动 

Windows 核心没启动：杀毒软件杀了，关闭杀毒软件重新安装客户端。或者其他软件，如clash等后台占用，解决方法卸载其他同类软件后重启电脑

不要开发前端，我会自行开发前端，你只需要留好前端需要的接口即可