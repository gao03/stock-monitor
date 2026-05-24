import AppKit
import Foundation
import Combine

enum AddStockError: LocalizedError, Equatable {
    case emptyCode
    case notFound(String)
    case duplicated(String)

    var errorDescription: String? {
        switch self {
        case .emptyCode:
            return "请输入股票代码"
        case .notFound(let code):
            return "未找到股票代码：\(code)"
        case .duplicated(let code):
            return "股票已存在：\(code)"
        }
    }
}

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
    let longbridgeClient: LongbridgeBridgeClient?

    private var refreshTask: Task<Void, Never>?
    private var longbridgeEventTask: Task<Void, Never>?
    private var longbridgeSyncTask: Task<Void, Never>?
    private var longbridgeRestartTask: Task<Void, Never>?
    private var longbridgeGeneration = 0
    private var longbridgeConfiguredKey: String?
    private var longbridgeSubscribedSymbols: Set<String> = []
    private let ruleEngine = MonitorRuleEngine()
    private let longbridgeQuoteMapper = LongbridgeQuoteMapper()
    private var lastNotificationAt: [String: Date] = [:]

    init(
        stockStore: StockStore,
        settingsStore: SettingsStore,
        quoteEngine: QuoteEngine,
        notificationService: NotificationService,
        longbridgeClient: LongbridgeBridgeClient? = nil
    ) {
        self.stockStore = stockStore
        self.settingsStore = settingsStore
        self.quoteEngine = quoteEngine
        self.notificationService = notificationService
        self.longbridgeClient = longbridgeClient
        self.stocks = stockStore.load()
        self.settings = settingsStore.load()
    }

    func startRefreshing() {
        refreshTask?.cancel()
        startLongbridgeIfNeeded()
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
        stopLongbridge()
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
            var appliedQuotes: [StockQuote] = []
            for quote in fetchedQuotes {
                if settings.longbridgeEnabled,
                   var currentQuote = nextQuotes[quote.symbol.cacheKey],
                   currentQuote.session == .streaming {
                    currentQuote.name = currentQuote.name.isEmpty ? quote.name : currentQuote.name
                    currentQuote.averagePrice = quote.averagePrice
                    currentQuote.highestPrice = max(currentQuote.highestPrice, quote.highestPrice)
                    currentQuote.lowestPrice = currentQuote.lowestPrice == 0 ? quote.lowestPrice : min(currentQuote.lowestPrice, quote.lowestPrice)
                    currentQuote.openPrice = currentQuote.openPrice == 0 ? quote.openPrice : currentQuote.openPrice
                    currentQuote.ma5 = quote.ma5
                    currentQuote.ma10 = quote.ma10
                    currentQuote.ma20 = quote.ma20
                    nextQuotes[quote.symbol.cacheKey] = currentQuote
                    appliedQuotes.append(currentQuote)
                } else {
                    nextQuotes[quote.symbol.cacheKey] = quote
                    appliedQuotes.append(quote)
                }
            }
            quotes = nextQuotes
            lastRefresh = Date()
            lastErrorMessage = nil
            evaluateMonitorRules(using: appliedQuotes)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addStock(_ stock: StockConfig) {
        stocks.append(stock)
        saveStocks()
        syncLongbridgeSubscriptions()
    }

    func addStock(code rawCode: String, showInTitle: Bool = true) async throws -> StockConfig {
        let code = normalizedStockCode(rawCode)
        guard !code.isEmpty else {
            throw AddStockError.emptyCode
        }

        guard let lookupResult = try await quoteEngine.lookupStock(code: code) else {
            throw AddStockError.notFound(code)
        }

        var stock = lookupResult.stock
        if stock.name.isEmpty {
            stock.name = lookupResult.quote.name
        }
        stock.showInTitle = showInTitle

        guard !stocks.contains(where: { $0.id == stock.id }) else {
            throw AddStockError.duplicated(stock.symbol.displayText)
        }

        stocks.append(stock)
        quotes[stock.symbol.cacheKey] = lookupResult.quote
        saveStocks()
        syncLongbridgeSubscriptions()
        return stock
    }

    func updateStock(_ stock: StockConfig) {
        guard let index = stocks.firstIndex(where: { $0.id == stock.id }) else { return }
        stocks[index] = stock
        saveStocks()
        syncLongbridgeSubscriptions()
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
        syncLongbridgeSubscriptions()
    }

    func updateSettings(_ next: AppSettings) {
        let previousSettings = settings
        settings = next
        settingsStore.save(next)
        if previousSettings.longbridgeEnabled != next.longbridgeEnabled {
            restartLongbridge()
        } else if previousSettings.longbridgeClientID != next.longbridgeClientID ||
            previousSettings.longbridgeRegion != next.longbridgeRegion ||
            previousSettings.longbridgeEnableOvernight != next.longbridgeEnableOvernight {
            scheduleLongbridgeRestart()
        }
    }

    func restartLongbridgeSidecar() {
        guard settings.longbridgeEnabled else {
            return
        }
        guard longbridgeClient != nil else {
            lastErrorMessage = "长桥 bridge 不可用"
            return
        }
        restartLongbridge()
    }

    private func saveStocks() {
        stockStore.save(stocks)
    }

    private func startLongbridgeIfNeeded() {
        guard settings.longbridgeEnabled else { return }
        guard longbridgeClient != nil else { return }
        guard !settings.longbridgeClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastErrorMessage = "长桥 OAuth Client ID 未配置"
            return
        }

        ensureLongbridgeEventTask()
        syncLongbridgeSubscriptions()
    }

    private func restartLongbridge() {
        longbridgeRestartTask?.cancel()
        longbridgeRestartTask = nil
        let generation = resetLongbridgeLocalState()
        let longbridgeClient = longbridgeClient
        Task { [weak self] in
            await longbridgeClient?.stop()
            await MainActor.run {
                guard let self, self.longbridgeGeneration == generation else { return }
                self.startLongbridgeIfNeeded()
            }
        }
    }

    private func scheduleLongbridgeRestart() {
        longbridgeRestartTask?.cancel()
        guard settings.longbridgeEnabled else { return }

        let generation = longbridgeGeneration
        longbridgeRestartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.longbridgeGeneration == generation else { return }
                self.restartLongbridge()
            }
        }
    }

    private func stopLongbridge() {
        resetLongbridgeLocalState()
        let longbridgeClient = longbridgeClient
        Task {
            await longbridgeClient?.stop()
        }
    }

    @discardableResult
    private func resetLongbridgeLocalState() -> Int {
        longbridgeGeneration += 1
        longbridgeEventTask?.cancel()
        longbridgeEventTask = nil
        longbridgeSyncTask?.cancel()
        longbridgeSyncTask = nil
        longbridgeRestartTask?.cancel()
        longbridgeRestartTask = nil
        longbridgeConfiguredKey = nil
        longbridgeSubscribedSymbols = []
        return longbridgeGeneration
    }

    private func ensureLongbridgeEventTask() {
        guard longbridgeEventTask == nil, let longbridgeClient else { return }
        longbridgeEventTask = Task { [weak self] in
            let stream = await longbridgeClient.events()
            for await event in stream {
                guard !Task.isCancelled else { break }
                self?.handleLongbridgeEvent(event)
            }
        }
    }

    private func syncLongbridgeSubscriptions() {
        guard settings.longbridgeEnabled, let longbridgeClient else { return }

        longbridgeSyncTask?.cancel()
        let generation = longbridgeGeneration
        let targetSymbols = Set(stocks.compactMap { $0.symbol.longbridgeSymbol })
        longbridgeSyncTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.configureLongbridgeIfNeeded(client: longbridgeClient, generation: generation)
                try Task.checkCancellation()
                guard self.isLongbridgeSyncCurrent(generation) else { return }

                let removedSymbols = Array(self.longbridgeSubscribedSymbols.subtracting(targetSymbols)).sorted()
                let addedSymbols = Array(targetSymbols.subtracting(self.longbridgeSubscribedSymbols)).sorted()

                if !removedSymbols.isEmpty {
                    try await longbridgeClient.unsubscribe(symbols: removedSymbols)
                }
                try Task.checkCancellation()
                guard self.isLongbridgeSyncCurrent(generation) else { return }

                if !addedSymbols.isEmpty {
                    try await longbridgeClient.subscribe(symbols: addedSymbols)
                }
                try Task.checkCancellation()
                guard self.isLongbridgeSyncCurrent(generation) else { return }

                self.longbridgeSubscribedSymbols = targetSymbols
                let snapshots = try await longbridgeClient.snapshot(symbols: Array(targetSymbols).sorted())
                try Task.checkCancellation()
                guard self.isLongbridgeSyncCurrent(generation) else { return }
                self.applyLongbridgeQuotes(snapshots)
            } catch is CancellationError {
                return
            } catch {
                if self.isLongbridgeSyncCurrent(generation) {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func configureLongbridgeIfNeeded(client: LongbridgeBridgeClient, generation: Int) async throws {
        let clientID = settings.longbridgeClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = longbridgeConfigurationKey(clientID: clientID)
        guard longbridgeConfiguredKey != key else { return }

        try await client.configure(
            clientID: clientID,
            region: settings.longbridgeRegion,
            enableOvernight: settings.longbridgeEnableOvernight
        )
        guard isLongbridgeSyncCurrent(generation),
              key == longbridgeConfigurationKey(clientID: settings.longbridgeClientID.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw CancellationError()
        }
        longbridgeConfiguredKey = key
        longbridgeSubscribedSymbols = []
    }

    private func isLongbridgeGenerationCurrent(_ generation: Int) -> Bool {
        generation == longbridgeGeneration
    }

    private func isLongbridgeSyncCurrent(_ generation: Int) -> Bool {
        isLongbridgeGenerationCurrent(generation) && settings.longbridgeEnabled
    }

    private func longbridgeConfigurationKey(clientID: String) -> String {
        [
            clientID,
            settings.longbridgeRegion.rawValue,
            settings.longbridgeEnableOvernight ? "overnight" : "regular"
        ].joined(separator: "|")
    }

    private func handleLongbridgeEvent(_ event: LongbridgeBridgeEvent) {
        switch event {
        case .started, .sdkPush:
            break
        case .ready:
            lastErrorMessage = nil
        case .authorizationRequired(let url):
            NSWorkspace.shared.open(url)
        case .quote(let payload):
            applyLongbridgeQuotes([payload])
        case .error(let message):
            if settings.longbridgeEnabled {
                lastErrorMessage = message
            }
        }
    }

    private func applyLongbridgeQuotes(_ payloads: [LongbridgeQuotePayload]) {
        guard !payloads.isEmpty else { return }

        var nextQuotes = quotes
        var appliedQuotes: [StockQuote] = []
        for payload in payloads {
            guard let stock = stock(forLongbridgeSymbol: payload.symbol),
                  let quote = longbridgeQuoteMapper.quote(
                    from: payload,
                    stock: stock,
                    existingQuote: nextQuotes[stock.symbol.cacheKey]
                  )
            else {
                continue
            }
            nextQuotes[stock.symbol.cacheKey] = quote
            appliedQuotes.append(quote)
        }

        guard !appliedQuotes.isEmpty else { return }
        quotes = nextQuotes
        lastRefresh = Date()
        lastErrorMessage = nil
        evaluateMonitorRules(using: appliedQuotes)
    }

    private func stock(forLongbridgeSymbol symbol: String) -> StockConfig? {
        let normalizedSymbol = symbol.uppercased()
        return stocks.first { stock in
            stock.symbol.longbridgeSymbol == normalizedSymbol
        }
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
