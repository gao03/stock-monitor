import Foundation

public struct QuoteEngine: Sendable {
    public var providers: [any QuoteProvider]

    public init(providers: [any QuoteProvider]) {
        self.providers = providers
    }

    public func fetchQuotes(for stocks: [StockConfig]) async throws -> [StockQuote] {
        guard !providers.isEmpty else { return [] }

        var quotesBySymbol: [StockSymbol: StockQuote] = [:]
        var remainingSymbols = stocks.map(\.symbol)
        var lastError: Error?

        for provider in providers where !remainingSymbols.isEmpty {
            do {
                let quoteMap = try await provider.quotes(for: remainingSymbols)
                quotesBySymbol.merge(quoteMap) { current, _ in current }
                remainingSymbols.removeAll { quoteMap[$0] != nil }
            } catch {
                lastError = error
            }
        }

        if quotesBySymbol.isEmpty, let lastError {
            throw lastError
        }

        return stocks.compactMap { stock in
            guard var quote = quotesBySymbol[stock.symbol] else { return nil }
            quote.symbol = stock.symbol
            return quote
        }
    }

    public func lookupStock(code: String) async throws -> StockLookupResult? {
        var lastError: Error?

        for provider in providers {
            guard let lookupProvider = provider as? any StockLookupProvider else { continue }
            do {
                if let result = try await lookupProvider.lookupStock(code: code) {
                    return result
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        return nil
    }
}
