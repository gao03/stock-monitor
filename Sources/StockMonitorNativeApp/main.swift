import AppKit
import StockMonitorNative

let app = NSApplication.shared
let delegate = StockMonitorAppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
