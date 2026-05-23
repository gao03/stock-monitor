import AppKit
import SwiftUI

final class StockMonitorAppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var statusController: StatusBarController!
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let operationStore = OperationStore()
        let stockStore = StockStore(operationStore: operationStore)
        let settingsStore = SettingsStore()
        let notificationService = NotificationService(settingsStore: settingsStore)
        let quoteEngine = QuoteEngine(
            providers: [
                EastMoneyQuoteProvider(),
                LongbridgeQuoteProviderPlaceholder()
            ]
        )

        appState = AppState(
            stockStore: stockStore,
            settingsStore: settingsStore,
            operationStore: operationStore,
            quoteEngine: quoteEngine,
            notificationService: notificationService
        )

        statusController = StatusBarController(appState: appState) { [weak self] in
            self?.showSettingsWindow()
        }
        statusController.start()

        notificationService.requestAuthorization()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusController?.stop()
    }

    private func showSettingsWindow() {
        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsRootView()
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Stock Monitor"
        window.center()
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

