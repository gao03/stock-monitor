import Foundation
import XCTest
@testable import StockMonitorNative

final class QuoteEngineTests: XCTestCase {
    func testFetchQuotesFallsBackToLaterProvidersForMissingSymbols() async throws {
        let aapl = StockSymbol(code: "AAPL", market: .usNASDAQ)
        let msft = StockSymbol(code: "MSFT", market: .usNASDAQ)
        let engine = QuoteEngine(providers: [
            StubQuoteProvider(quotes: [aapl: quote(for: aapl, price: 100)]),
            StubQuoteProvider(quotes: [msft: quote(for: msft, price: 200)])
        ])

        let quotes = try await engine.fetchQuotes(for: [
            StockConfig(symbol: aapl),
            StockConfig(symbol: msft)
        ])

        XCTAssertEqual(quotes.map(\.symbol), [aapl, msft])
        XCTAssertEqual(quotes.map(\.price), [100, 200])
    }

    func testFetchQuotesThrowsWhenEveryProviderFailsAndNoQuotesAreFetched() async {
        let symbol = StockSymbol(code: "AAPL", market: .usNASDAQ)
        let engine = QuoteEngine(providers: [
            StubQuoteProvider(error: StubQuoteError.failed),
            StubQuoteProvider(error: StubQuoteError.failed)
        ])

        do {
            _ = try await engine.fetchQuotes(for: [StockConfig(symbol: symbol)])
            XCTFail("Expected fetchQuotes to throw")
        } catch StubQuoteError.failed {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func quote(for symbol: StockSymbol, price: Decimal) -> StockQuote {
        StockQuote(
            symbol: symbol,
            name: symbol.code,
            price: price,
            percentChange: 0,
            highestPrice: price,
            openPrice: price,
            previousClose: price
        )
    }
}

private enum StubQuoteError: Error {
    case failed
}

private struct StubQuoteProvider: QuoteProvider {
    var quotes: [StockSymbol: StockQuote] = [:]
    var error: StubQuoteError?

    func quotes(for symbols: [StockSymbol]) async throws -> [StockSymbol: StockQuote] {
        if let error {
            throw error
        }

        return symbols.reduce(into: [:]) { result, symbol in
            result[symbol] = quotes[symbol]
        }
    }
}
