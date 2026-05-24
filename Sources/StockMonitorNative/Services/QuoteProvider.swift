import Foundation

public protocol QuoteProvider: Sendable {
    func quote(for symbol: StockSymbol) async throws -> StockQuote?
    func quotes(for symbols: [StockSymbol]) async throws -> [StockSymbol: StockQuote]
}

public struct StockLookupResult: Sendable, Equatable {
    public var stock: StockConfig
    public var quote: StockQuote

    public init(stock: StockConfig, quote: StockQuote) {
        self.stock = stock
        self.quote = quote
    }
}

public protocol StockLookupProvider: QuoteProvider {
    func lookupStock(code: String) async throws -> StockLookupResult?
}

public extension QuoteProvider {
    func quote(for symbol: StockSymbol) async throws -> StockQuote? {
        try await quotes(for: [symbol])[symbol]
    }
}

public enum QuoteProviderError: Error, Sendable, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid quote provider URL."
        case .invalidResponse:
            return "Quote provider returned an invalid response."
        case .decodingFailed:
            return "Quote provider response could not be decoded."
        }
    }
}
