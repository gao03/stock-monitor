# StockMonitorNative

Native macOS menu bar stock monitor.

## Scope

- Native status bar app with `NSStatusItem`.
- SwiftUI menu bar popover for quotes, stock rules, and core configuration.
- JSON persistence under `Application Support/StockMonitorNative`.
- EastMoney quote polling for A shares, Hong Kong stocks, and US stocks.
- Optional Longbridge sidecar for OAuth-based realtime quotes.
- Sina supplemental quote support for US pre-market/after-hours prices.
- Rule engine compatible with the legacy expressions: `3%`, `+3%`, `-3%`, `9+`, `9-`, `+3`, `-3`, `|3%`, `|+3%`, `|-3%`.
- System notifications with URL open behavior.

The WebView/screenshot chart feature is intentionally not included.

## Build

Open `StockMonitorNative.xcodeproj` in Xcode and select the `StockMonitorNativeApp` scheme.

```bash
cargo build --manifest-path rust/longbridge-bridge/Cargo.toml
swift build
swift run StockMonitorNative
swift test
xcodebuild -project StockMonitorNative.xcodeproj -scheme StockMonitorNativeApp -destination platform=macOS test
```

This project targets macOS 14+. A matching Xcode/Command Line Tools installation is required.

`swift test` runs the XCTest suite first. The final `Swift Testing` line may report `0 tests in 0 suites`; that only means there are no tests using the newer Swift Testing framework.

When launched with `swift run`, the app runs as an unbundled executable. System notifications are disabled in that mode because `UNUserNotificationCenter` requires an app bundle identity. Notifications are enabled when the app is packaged as a `.app`.

Longbridge realtime quotes require the Rust sidecar binary at
`rust/longbridge-bridge/target/debug/longbridge-bridge` during development. You
can override the path with `STOCK_MONITOR_LONGBRIDGE_BRIDGE`.
