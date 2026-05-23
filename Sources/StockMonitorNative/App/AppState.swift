import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var stocks: [StockConfig] = []
    @Published var quotes: [String: StockQuote] = [:]
    @Published var operations: [OperationRecord] = []
    @Published var settings: AppSettings
    @Published var selectedStockID: StockConfig.ID?
    @Published var lastRefresh: Date?
    @Published var lastErrorMessage: String?

    let stockStore: StockStore
    let settingsStore: SettingsStore
    let operationStore: OperationStore
    let quoteEngine: QuoteEngine
    let notificationService: NotificationService

    private var refreshTask: Task<Void, Never>?
    private let ruleEngine = MonitorRuleEngine()
    private var lastNotificationAt: [String: Date] = [:]

    init(
        stockStore: StockStore,
        settingsStore: SettingsStore,
        operationStore: OperationStore,
        quoteEngine: QuoteEngine,
        notificationService: NotificationService
    ) {
        self.stockStore = stockStore
        self.settingsStore = settingsStore
        self.operationStore = operationStore
        self.quoteEngine = quoteEngine
        self.notificationService = notificationService
        self.stocks = stockStore.load()
        self.settings = settingsStore.load()
        self.operations = operationStore.list(limit: 200)
        self.selectedStockID = stocks.first?.id
    }

    var selectedStock: StockConfig? {
        guard let selectedStockID else { return stocks.first }
        return stocks.first { $0.id == selectedStockID }
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
        selectedStockID = stock.id
        saveStocks(operation: .addStock, stock: stock, description: "添加股票")
    }

    func updateStock(_ stock: StockConfig) {
        guard let index = stocks.firstIndex(where: { $0.id == stock.id }) else { return }
        stocks[index] = stock
        saveStocks(operation: .updateConfig, stock: stock, description: "更新股票配置")
    }

    func updateSelectedStock(_ stock: StockConfig) {
        guard let selectedStockID,
              let index = stocks.firstIndex(where: { $0.id == selectedStockID })
        else {
            updateStock(stock)
            return
        }
        stocks[index] = stock
        self.selectedStockID = stock.id
        saveStocks(operation: .updateConfig, stock: stock, description: "更新股票配置")
    }

    func deleteSelectedStock() {
        guard let stock = selectedStock else { return }
        stocks.removeAll { $0.id == stock.id }
        quotes.removeValue(forKey: stock.symbol.cacheKey)
        selectedStockID = stocks.first?.id
        saveStocks(operation: .removeStock, stock: stock, description: "删除股票")
    }

    func addRule(_ rule: MonitorRule, to stock: StockConfig) {
        var updated = stock
        updated.monitorRules.append(rule)
        updateStock(updated)
        appendOperation(type: .addMonitor, stock: stock, description: "添加监控规则: \(rule.displayText)")
    }

    func deleteRules(at offsets: IndexSet, from stock: StockConfig) {
        var updated = stock
        let removed = offsets.map { updated.monitorRules[$0].displayText }.joined(separator: ", ")
        for index in offsets.sorted(by: >) {
            updated.monitorRules.remove(at: index)
        }
        updateStock(updated)
        appendOperation(type: .removeMonitor, stock: stock, description: "删除监控规则: \(removed)")
    }

    func updateSettings(_ next: AppSettings) {
        settings = next
        settingsStore.save(next)
    }

    func clearOperations() {
        operationStore.clear()
        operations = []
    }

    private func saveStocks(operation type: OperationType, stock: StockConfig, description: String) {
        stockStore.save(stocks)
        appendOperation(type: type, stock: stock, description: description)
    }

    private func appendOperation(type: OperationType, stock: StockConfig, description: String) {
        operationStore.append(
            OperationRecord(
                type: type,
                stockCode: stock.symbol.code,
                stockName: stock.name,
                detail: description
            )
        )
        operations = operationStore.list(limit: 200)
    }

    private func evaluateMonitorRules(using fetchedQuotes: [StockQuote]) {
        guard settings.notificationsEnabled else { return }

        let quoteMap = Dictionary(uniqueKeysWithValues: fetchedQuotes.map { ($0.symbol.cacheKey, $0) })
        for stock in stocks where stock.alertsEnabled {
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
