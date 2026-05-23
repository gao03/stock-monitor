import AppKit

public final class StockMonitorAppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var statusController: StatusBarController!

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let stockStore = StockStore()
        let settingsStore = SettingsStore()
        let notificationService = NotificationService(settingsStore: settingsStore)
        let quoteEngine = QuoteEngine(
            providers: [
                EastMoneyQuoteProvider()
            ]
        )

        appState = AppState(
            stockStore: stockStore,
            settingsStore: settingsStore,
            quoteEngine: quoteEngine,
            notificationService: notificationService
        )

        statusController = StatusBarController(appState: appState)
        statusController.start()

        notificationService.requestAuthorization()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusController?.stop()
    }
}
