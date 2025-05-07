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

