# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
