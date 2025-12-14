## 1.5.0

- Reused a shared `MDnsClient` for mDNS scanning to avoid multiple bindings to port 5353; on Apple platforms, mDNS results now come via a Flutter MethodChannel (Bonjour).
- Removed `native_mdns_scanner` and bundled FFI binaries to shrink the package; cross-platform scanning now relies on Dart and the MethodChannel path.
- Kept the v1.4 AirPlay three-type enum (`airplayRxVideo`/`airplayRxAudio`/`airplayTx`) and `isAirplay*` helpers to preserve API compatibility.
- Added an `enableMdns` parameter to `findDevices` and `findDevicesAsJson*` to let users skip mDNS in restricted network environments.
- Added a `flutter` SDK dependency in `pubspec.yaml` to support the MethodChannel; pure Dart still uses `multicast_dns`/stub and does not touch Flutter APIs.

## 1.4.0

- **BREAKING CHANGE**: Simplified AirPlay device type enum from 5 types to 3 types for cleaner classification:
  - Removed: `airplayTxMobile`, `airplayTxDesktop`, and backward-compatible `airplay` type
  - Kept: `airplayRxVideo`, `airplayRxAudio`, `airplayTx`
- Implemented direct mDNS service type mapping for AirPlay device classification:
  - `_airplay._tcp` → `airplayRxVideo` (AirPlay video receiver)
  - `_raop._tcp` → `airplayRxAudio` (AirPlay audio receiver)  
  - `_companion-link._tcp` → `airplayTx` (AirPlay transmitter)
- Updated `scanAirplayTxDevices` to use `_companion-link._tcp` instead of `_raop._tcp` for better device categorization
- Enhanced `DiscoveryService` device categorization logic to properly handle the new simplified AirPlay types
- Improved AirPlay device getter methods (`isAirplayTx`, `isAirplay`, `isAirplayRx`) to work with simplified enum structure
- All existing `isAirplay` checks continue to work, maintaining backward compatibility for device detection logic
- Updated device classification logic to be more straightforward and maintainable

## 1.3.0

- Enhanced output format: added `dlna_rx`, `dlna_tx`, `airplay_rx`, `airplay_tx`, and `count` fields to the JSON result for more granular device categorization.
- Updated README.md:
  - Output format and device information examples now reflect the new fields and structure.
  - Added a command-line output example with sensitive information masked (***).
- Improved example code:
  - Example now prints AirPlay RX/TX results in addition to Chromecast and DLNA.
  - Comments and output are now in English.
- CLI/JSON output: sensitive information (such as device name, IP, ID) is masked with `***` in documentation and sample outputs to protect user privacy.
- All API parameters previously named `timeout` have been renamed to `scanDuration` for clarity. Please update your code and CLI usage accordingly.
- Minor documentation and code cleanups.

## 1.2.0

- Fixed an issue where the logger could cause a "bad state: Future already completed" error in certain scenarios
- Added usage examples and documentation for AirPlay RX and AirPlay TX device discovery

## 1.1.0

- Added a comprehensive event notification system for real-time device discovery updates
- Implemented event-based architecture with DeviceFoundEvent, SearchStartedEvent, SearchCompleteEvent, and SearchErrorEvent
- Improved search efficiency by making DLNA Renderer and MediaServer scans run in parallel
- Added callback mechanism to scanChromecastDevices and scanDlnaDevices functions for immediate device discovery notifications
- Created new examples demonstrating event-driven device discovery in both CLI and Flutter applications
- Enhanced user experience with real-time device discovery feedback
- Exposed deviceEvents stream from ChromecastDlnaFinder for application integration

## 1.0.5

- Implemented device duplication detection mechanism to ensure each device appears only once in results
- Added device ID-based duplication detection during mDNS scanning to solve the issue of multiple responses from the same Chromecast device


## 1.0.4

- Enhanced localization file path detection for various usage scenarios (global CLI, library dependency, Flutter app)
- Added support for finding locale files in global installation directories
- Implemented automatic locale file detection in Flutter applications (Android, iOS, macOS, Windows, Linux)
- Added embedded translations as fallback when locale files cannot be found
- Improved error logging with detailed path information for better diagnostics
- Updated asset configuration in pubspec.yaml to ensure proper packaging of locale files

## 1.0.3

- Major refactor of logger system: removed LogMode/suppressOutput, now uses setOutputs({LoggerOutput.stderr, ...}) for flexible log output control (stderr, stdout, broadcast, or silent).
- Support for logger broadcast stream for app/Flutter UI log listening.
- Added dependency injection for logger in ChromecastDlnaFinder (app/desktop can inject their own logger instance).
- Internationalization (i18n) greatly expanded: now supports English, Traditional Chinese, Simplified Chinese, Japanese, German, French, Spanish, Italian, Russian, Portuguese, Hong Kong Chinese, and more. Fallback order: language-region-variant → language-region → language.
- Improved locale fallback logic and file detection (e.g. zh_TW-Hant → zh_TW → zh).
- Updated CLI and API usage to match new logger and i18n system.
- README.md fully rewritten and enhanced to reflect new architecture, usage, and features.
- Test suite updated to match new logger API and i18n logic.
- Various bug fixes and code cleanups.
