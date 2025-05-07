## 1.1.0

- Major refactor of logger system: removed LogMode/suppressOutput, now uses setOutputs({LoggerOutput.stderr, ...}) for flexible log output control (stderr, stdout, broadcast, or silent).
- Support for logger broadcast stream for app/Flutter UI log listening.
- Added dependency injection for logger in ChromecastDlnaFinder (app/desktop can inject their own logger instance).
- Internationalization (i18n) greatly expanded: now supports English, Traditional Chinese, Simplified Chinese, Japanese, German, French, Spanish, Italian, Russian, Portuguese, Hong Kong Chinese, and more. Fallback order: language-region-variant → language-region → language.
- Improved locale fallback logic and file detection (e.g. zh_TW-Hant → zh_TW → zh).
- Updated CLI and API usage to match new logger and i18n system.
- README.md fully rewritten and enhanced to reflect new architecture, usage, and features.
- Test suite updated to match new logger API and i18n logic.
- Various bug fixes and code cleanups.

## 1.0.0

- Initial version.
