import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var stocks: [StockConfig] = []
    @Published var quotes: [String: StockQuote] = [:]
    @Published var settings: AppSettings
    @Published var lastRefresh: Date?
    @Published var lastErrorMessage: String?

    let stockStore: StockStore
    let settingsStore: SettingsStore
    let quoteEngine: QuoteEngine
    let notificationService: NotificationService

    private var refreshTask: Task<Void, Never>?
    private let ruleEngine = MonitorRuleEngine()
    private var lastNotificationAt: [String: Date] = [:]

    init(
        stockStore: StockStore,
        settingsStore: SettingsStore,
        quoteEngine: QuoteEngine,
        notificationService: NotificationService
    ) {
        self.stockStore = stockStore
        self.settingsStore = settingsStore
        self.quoteEngine = quoteEngine
        self.notificationService = notificationService
        self.stocks = stockStore.load()
        self.settings = settingsStore.load()
    }

    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshOnce()

            while !Task.isCancelled {
                let interval = await MainActor.run { self.settings.refreshInterval }
                try? await Task.sleep(for: .seconds(max(2, interval)))
                await self.refreshOnce()
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshOnce() async {
        let currentStocks = stocks
        guard !currentStocks.isEmpty else {
            quotes = [:]
            lastRefresh = Date()
            return
        }

        do {
            let fetchedQuotes = try await quoteEngine.fetchQuotes(for: currentStocks)
            var nextQuotes = quotes
            for quote in fetchedQuotes {
                nextQuotes[quote.symbol.cacheKey] = quote
            }
            quotes = nextQuotes
            lastRefresh = Date()
            lastErrorMessage = nil
            evaluateMonitorRules(using: fetchedQuotes)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addStock(_ stock: StockConfig) {
        stocks.append(stock)
        saveStocks()
    }

    func updateStock(_ stock: StockConfig) {
        guard let index = stocks.firstIndex(where: { $0.id == stock.id }) else { return }
        stocks[index] = stock
        saveStocks()
    }

    func moveStock(draggedID: StockConfig.ID, to targetID: StockConfig.ID) -> Bool {
        guard draggedID != targetID,
              let sourceIndex = stocks.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = stocks.firstIndex(where: { $0.id == targetID })
        else { return false }

        let stock = stocks.remove(at: sourceIndex)
        stocks.insert(stock, at: min(targetIndex, stocks.count))
        return true
    }

    func saveStockOrder() {
        stockStore.save(stocks)
    }

    func deleteStock(_ stock: StockConfig) {
        stocks.removeAll { $0.id == stock.id }
        quotes.removeValue(forKey: stock.symbol.cacheKey)
        saveStocks()
    }

    func updateSettings(_ next: AppSettings) {
        settings = next
        settingsStore.save(next)
    }

    private func saveStocks() {
        stockStore.save(stocks)
    }

    private func evaluateMonitorRules(using fetchedQuotes: [StockQuote]) {
        guard settings.notificationsEnabled else { return }

        let quoteMap = Dictionary(uniqueKeysWithValues: fetchedQuotes.map { ($0.symbol.cacheKey, $0) })
        for stock in stocks {
            guard let quote = quoteMap[stock.symbol.cacheKey] else { continue }

            for rule in stock.monitorRules where ruleEngine.isTriggered(
                rule: rule,
                previousClose: quote.previousClose,
                costPrice: stock.costPrice,
                currentPrice: quote.price
            ) {
                guard canSendNotification(
                    key: "\(stock.id)-\(rule.rawValue)",
                    interval: settings.duplicateAlertInterval
                ) else { continue }
                notificationService.notify(
                    title: quote.name,
                    subtitle: "规则: \(rule.displayText)",
                    body: "当前价格 \(quote.price.formattedPrice), 涨幅 \(quote.changePercent.formattedPercent)",
                    url: XueqiuURLBuilder.url(for: stock.symbol)
                )
            }

            if ruleEngine.shouldTriggerReturnToCost(config: stock, quote: quote),
               canSendNotification(key: "\(stock.id)-return-to-cost", interval: settings.returnToCostAlertInterval) {
                notificationService.notify(
                    title: quote.name,
                    subtitle: "规则: 回本",
                    body: "当前价格 \(quote.price.formattedPrice), 成本 \(stock.costPrice.formattedPrice)",
                    url: XueqiuURLBuilder.url(for: stock.symbol)
                )
            }
        }
    }

    private func canSendNotification(key: String, interval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastNotificationAt[key], now.timeIntervalSince(last) < interval {
            return false
        }
        lastNotificationAt[key] = now
        return true
    }
}
