# StockMonitorNative

macOS native rewrite of the original Go menu bar stock monitor.

## Scope

- Native status bar app with `NSStatusItem`.
- SwiftUI menu bar popover for quotes, stock rules, and core configuration.
- JSON persistence under `Application Support/StockMonitorNative`.
- EastMoney quote polling for A shares, Hong Kong stocks, and US stocks.
- Sina supplemental quote support for US pre-market/after-hours prices.
- Rule engine compatible with the Go expressions: `3%`, `+3%`, `-3%`, `9+`, `9-`, `+3`, `-3`, `|3%`, `|+3%`, `|-3%`.
- System notifications with URL open behavior.

The WebView/screenshot chart feature is intentionally not included.

## Build

```bash
swift build
swift run StockMonitorNative
```

This project targets macOS 14+. A matching Xcode/Command Line Tools installation is required.

When launched with `swift run`, the app runs as an unbundled executable. System notifications are disabled in that mode because `UNUserNotificationCenter` requires an app bundle identity. Notifications are enabled when the app is packaged as a `.app`.
