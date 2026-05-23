import Foundation

public struct QuoteEngine: Sendable {
    public var providers: [any QuoteProvider]

    public init(providers: [any QuoteProvider]) {
        self.providers = providers
    }

    public func fetchQuotes(for stocks: [StockConfig]) async throws -> [StockQuote] {
        guard let provider = providers.first else { return [] }
        let symbols = stocks.map(\.symbol)
        let quoteMap = try await provider.quotes(for: symbols)
        return stocks.compactMap { stock in
            quoteMap[stock.symbol]
        }
    }
}

public struct LongbridgeQuoteProviderPlaceholder: QuoteProvider {
    public init() {}

    public func quotes(for symbols: [StockSymbol]) async throws -> [StockSymbol: StockQuote] {
        [:]
    }
}
