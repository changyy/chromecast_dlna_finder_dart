# Chromecast DLNA Finder

[![pub package](https://img.shields.io/pub/v/chromecast_dlna_finder.svg)](https://pub.dev/packages/chromecast_dlna_finder)

A Dart package for discovering Chromecast, DLNA, and AirPlay devices on your local network, providing easy-to-use APIs for scanning, categorizing, and interacting with these devices.

## Features

- 🔍 Scan for all Chromecast, DLNA, and AirPlay devices on your local network
- 📊 Automatic device categorization (Chromecast Dongle, Chromecast Audio, DLNA Renderer, DLNA Media Server, AirPlay RX Video, AirPlay RX Audio, AirPlay TX)
- 🌐 Support for both command-line tools and Dart/Flutter/desktop applications
- 🔄 Continuous scanning mode support
- 🌍 Multilingual support (English, Traditional Chinese, Simplified Chinese, Japanese, German, French, Spanish, Italian, Russian, Portuguese, Hong Kong Chinese, and more)
- 📱 Cross-platform (macOS, Linux, Windows, Android, iOS)
- 🖥️ Logger system with flexible output (stderr, stdout, broadcast for app UI)

## Installation

Use Dart's `pub` package manager to install:

```bash
dart pub add chromecast_dlna_finder
```

Or manually add it to your `pubspec.yaml` file:

```yaml
dependencies:
  chromecast_dlna_finder: ^1.5.0
```

## What's new in v1.5.0

- mDNS 掃描改用共用 `MDnsClient`（避免重複 bind 5353），Apple 平台則透過 Flutter MethodChannel (Bonjour) 查詢。
- 移除原生 `native_mdns_scanner` / FFI 二進位依賴，發佈體積更小，Flutter 專案需確保已加入本套件提供的 MethodChannel plug-in。
- API 仍維持 v1.4 的 AirPlay 3 型別（RX Video / RX Audio / TX）與對應的 `isAirplay*` 判斷，保持既有相容性。
- `findDevices`/`findDevicesAsJson*` 新增 `enableMdns` 參數，方便在受限網路環境下暫停 mDNS。

## ⚠️ Breaking Changes in v1.4.0

**AirPlay Device Type Simplification**: The AirPlay device type enumeration has been simplified from 5 types to 3 types for cleaner classification:

- **Removed types**: `airplayTxMobile`, `airplayTxDesktop`, and backward-compatible `airplay` type
- **Kept types**: `airplayRxVideo`, `airplayRxAudio`, `airplayTx`

**Migration Guide**:
- If you were checking for `DeviceType.airplayTxMobile` or `DeviceType.airplayTxDesktop`, use `DeviceType.airplayTx` instead
- If you were checking for the generic `DeviceType.airplay`, use the specific type (`airplayRxVideo`, `airplayRxAudio`, or `airplayTx`) or the helper methods (`isAirplay`, `isAirplayRx`, `isAirplayTx`)
- All existing `isAirplay*` getter methods continue to work and maintain backward compatibility

**New Direct mDNS Service Mapping**:
- `_airplay._tcp` → `airplayRxVideo` (AirPlay video receiver)
- `_raop._tcp` → `airplayRxAudio` (AirPlay audio receiver)  
- `_companion-link._tcp` → `airplayTx` (AirPlay transmitter)

## Architecture Overview

The package follows a modular architecture:

```
lib/
├── chromecast_dlna_finder.dart    # Main export file
└── src/
    ├── chromecast_dlna_finder_base.dart  # Core functionality
    ├── discovery/                  # Device discovery modules
    │   ├── device.dart            # Device model & type definitions
    │   ├── discovery_service.dart  # Main discovery orchestrator
    │   ├── mdns_scanner.dart      # Chromecast discovery via mDNS
    │   ├── ssdp_scanner.dart      # DLNA discovery via SSDP
    │   └── cached_device.dart     # Device caching mechanism
    ├── locales/                   # Internationalization
    │   ├── en.json                # English strings
    │   ├── zh_TW.json             # Traditional Chinese
    │   ├── zh_CN.json             # Simplified Chinese
    │   ├── ja.json                # Japanese
    │   ├── de.json                # German
    │   ├── fr.json                # French
    │   ├── es.json                # Spanish
    │   ├── it.json                # Italian
    │   ├── ru.json                # Russian
    │   ├── pt.json                # Portuguese
    │   ├── zh_HK.json             # Hong Kong Chinese
    │   └── ...                    # More languages
    └── util/                      # Utility classes
        ├── dlna_device_utils.dart  # DLNA-specific helpers
        ├── localization.dart      # Localization infrastructure
        ├── localization_manager.dart # Localization logic
        ├── logger.dart            # Logging system
        └── platform_info.dart     # Platform detection
```

**Key Components:**

- **ChromecastDlnaFinder**: Main entry point for all operations
- **Discovery Service**: Coordinates the scanning process between different protocols
- **Device Model**: Unified representation of both Chromecast and DLNA devices
- **Scanner Modules**: Specialized modules for each protocol (mDNS, SSDP)
- **Localization System**: Custom i18n implementation for multilingual support with fallback (e.g. zh_TW_Hant → zh_TW → zh)
- **Logger**: Flexible logger supporting stderr, stdout, and broadcast (for app/Flutter UI)

## Usage

### As a Command-Line Tool

Install the CLI tool globally:

```bash
dart pub global activate chromecast_dlna_finder
```

Run a scan:

```bash
chromecast_dlna_finder --scan-duration 5
```

Command-line options:

```
Options:
  -h, --help            Show help information
  -t, --scan-duration=<seconds>  Scan duration in seconds (default: 5)
  -m, --minify          Output minified JSON
  -q, --quiet           Suppress progress messages
  -d, --debug           Enable verbose debug information
  -l, --lang=<language>  Specify language (e.g., en, zh-TW, ja, de, fr, es, it, ru, pt, zh-HK, zh-CN)
```

### In Dart/Flutter/PC App Code

```dart
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';

Future<void> main() async {
  // Initialize logger for app/Flutter UI log listening
  final logger = AppLogger();
  logger.setOutputs({LoggerOutput.broadcast});
  await logger.init();

  // Listen to log stream (for UI or custom handling)
  final subscription = logger.broadcastStream?.listen((record) {
    print('[APP LOG][${record.level}] ${record.message}');
  });

  // Initialize the scanner with injected logger
  final finder = ChromecastDlnaFinder(logger: logger);

  // Scan for devices
  final devices = await finder.findDevices(scanDuration: Duration(seconds: 5));

  // Output all discovered devices
  print('Discovered Chromecast devices:');
  for (final device in devices['chromecast'] ?? []) {
    print('- [32m${device.name}[0m (${device.ip})');
  }

  print('Discovered DLNA devices:');
  for (final device in devices['dlna'] ?? []) {
    print('- [34m${device.name}[0m (${device.ip})');
  }

  // New: AirPlay RX and TX output
  print('Discovered AirPlay RX devices:');
  for (final device in devices['airplay_rx'] ?? []) {
    print('- [35m${device.name}[0m (${device.ip})');
  }

  print('Discovered AirPlay TX devices:');
  for (final device in devices['airplay_tx'] ?? []) {
    print('- [36m${device.name}[0m (${device.ip})');
  }

  // Release resources
  await finder.dispose();
  await logger.dispose();
  await subscription?.cancel();
}
```

## Output Format

The scan results are output in the following JSON structure (fields vary depending on actual scan results):

```json
{
  "all": [ ... ],
  "chromecast": [ ... ],
  "dlna": [ ... ],
  "dlna_rx": [ ... ],
  "dlna_tx": [ ... ],
  "airplay": [ ... ],
  "airplay_rx": [ ... ],
  "airplay_tx": [ ... ],
  "count": {
    "chromecast": { "total": 1, "rx": 1, "tx": 0 },
    "dlna": { "total": 1, "rx": 1, "tx": 0 },
    "airplay": { "total": 3, "rx": 3, "tx": 3 }
  },
  "error": [],
  "status": true
}
```

## Device Information

Each device object contains the following information (sensitive information is replaced with ***):

```json
{
  "name": "***",
  "ip": "***",
  "type": "chromecastDongle",
  "model": "***",
  "location": "***",
  "id": "***",
  "friendlyName": "***",
  "port": 8009,
  "extra": { /* ...extra device info... */ },
  "mdnsTypes": [ "_airplay._tcp" ]
}
```

**Available Device Types**:
- `chromecastDongle`, `chromecastAudio` - Chromecast devices
- `dlnaRenderer`, `dlnaMediaServer` - DLNA devices  
- `airplayRxVideo`, `airplayRxAudio`, `airplayTx` - AirPlay devices (v1.4.0+)

## Command Line Example (Sensitive Information Hidden)

```bash
% dart bin/chromecast_dlna_finder.dart
[2025-05-22 13:23:42.446][INFO] [Config] Logging system configured: outputs={LoggerOutput.stderr}, minLevel=AppLogLevel.info
{
  "all": [
    { "name": "***", "ip": "***", "type": "chromecastDongle", ... },
    { "name": "***", "ip": "***", "type": "dlnaRenderer", ... },
    { "name": "***", "ip": "***", "type": "airplayRxVideo", ... }
    // ... others ...
  ],
  "chromecast": [ { "name": "***", "ip": "***", ... } ],
  "dlna": [ { "name": "***", "ip": "***", ... } ],
  "airplay": [ { "name": "***", "ip": "***", ... } ],
  "airplay_rx": [ { "name": "***", "ip": "***", ... } ],
  "airplay_tx": [ { "name": "***", "ip": "***", ... } ],
  "dlna_rx": [ { "name": "***", "ip": "***", ... } ],
  "dlna_tx": [],
  "count": {
    "chromecast": { "total": 1, "rx": 1, "tx": 0 },
    "dlna": { "total": 1, "rx": 1, "tx": 0 },
    "airplay": { "total": 3, "rx": 3, "tx": 3 }
  },
  "error": [],
  "status": true
}
```

## Advanced Usage

### AirPlay Device Classification (v1.4.0+)

```dart
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';

Future<void> main() async {
  final finder = ChromecastDlnaFinder();
  final devices = await finder.findDevices(scanDuration: Duration(seconds: 5));
  
  for (final device in devices['all'] ?? []) {
    if (device.isAirplay) {
      print('AirPlay Device: ${device.name}');
      print('  Type: ${device.type}');
      print('  RX Video: ${device.isAirplayRxVideo}');
      print('  RX Audio: ${device.isAirplayRxAudio}');
      print('  TX: ${device.isAirplayTx}');
      print('  mDNS Types: ${device.mdnsTypes}');
    }
  }
  
  await finder.dispose();
}
```

### Getting Device Control URLs (DLNA Renderers Only)

```dart
import 'package:chromecast_dlna_finder/chromecast_dlna_finder.dart';

Future<void> main() async {
  final finder = ChromecastDlnaFinder();
  final devices = await finder.findDevices(scanDuration: Duration(seconds: 5));
  for (final device in devices['dlna_renderer'] ?? []) {
    print('Renderer: ${device.name}');
    print('  - AVTransport control URL: ${device.avTransportControlUrl}');
    print('  - Rendering control URL: ${device.renderingControlUrl}');
  }
  await finder.dispose();
}
```

### Logger Output Control

- To output logs to stderr (CLI):
  ```dart
  AppLogger().setOutputs({LoggerOutput.stderr});
  ```
- To output logs to broadcast stream (for app/Flutter UI):
  ```dart
  AppLogger().setOutputs({LoggerOutput.broadcast});
  ```
- To disable all logs:
  ```dart
  AppLogger().setOutputs({});
  ```

## Multilingual Support & Fallback

- Supported languages: English, Traditional Chinese (zh_TW), Simplified Chinese (zh_CN, zh), Japanese (ja), German (de), French (fr), Spanish (es), Italian (it), Russian (ru), Portuguese (pt), Hong Kong Chinese (zh_HK), and more.
- Fallback order: language-region-variant → language-region → language (e.g. zh_TW_Hant → zh_TW → zh)
- You can specify language via CLI `-l` or in code via `LocalizationManager().init(locale: 'ja')`.

## Running Tests

This package includes comprehensive tests. To run them with detailed output:

```bash
# Run all tests with expanded output
dart test --reporter expanded

# Run specific test file
dart test test/scanners_mock_test.dart --reporter expanded
```

## Network Requirements

- Chromecast discovery uses mDNS (multicast DNS), requiring UDP port 5353
- DLNA discovery uses SSDP protocol, requiring UDP port 1900 and related HTTP ports

## License

MIT

## Contributing

Contributions welcome! Please submit issues and suggestions to the [GitHub repository](https://github.com/changyy/chromecast_dlna_finder_dart).
