import Foundation

public protocol QuoteProvider: Sendable {
    func quote(for symbol: StockSymbol) async throws -> StockQuote?
    func quotes(for symbols: [StockSymbol]) async throws -> [StockSymbol: StockQuote]
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
