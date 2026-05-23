import Foundation
import XCTest
@testable import StockMonitorNative

final class EastMoneyQuoteProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testQuotesMatchCodesCaseInsensitively() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {
              "data": {
                "diff": [
                  {
                    "f2": 123.45,
                    "f3": 1.23,
                    "f12": "aapl",
                    "f13": 105,
                    "f14": "Apple",
                    "f15": 124.00,
                    "f16": 122.00,
                    "f17": 121.00,
                    "f18": 121.95,
                    "f232": ""
                  }
                ]
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }

        let provider = EastMoneyQuoteProvider(
            session: .mocked,
            afterHoursProvider: nil,
            includesUSAfterHoursSupplement: false
        )
        let symbol = StockSymbol(code: "AAPL", market: .usNASDAQ)

        let quotes = try await provider.quotes(for: [symbol])

        XCTAssertEqual(quotes[symbol]?.price, Decimal(string: "123.45"))
        XCTAssertEqual(quotes[symbol]?.symbol.code, "AAPL")
    }

    func testQuotesDecodeDecimalFieldsFromStrings() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {
              "data": {
                "diff": [
                  {
                    "f2": "123.45",
                    "f3": "1.23",
                    "f12": "aapl",
                    "f13": "105",
                    "f14": "Apple",
                    "f15": "124.00",
                    "f16": "122.00",
                    "f17": "121.00",
                    "f18": "121.95",
                    "f232": ""
                  }
                ]
              }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }

        let provider = EastMoneyQuoteProvider(
            session: .mocked,
            afterHoursProvider: nil,
            includesUSAfterHoursSupplement: false
        )
        let symbol = StockSymbol(code: "AAPL", market: .usNASDAQ)

        let quote = try await provider.quotes(for: [symbol])[symbol]

        XCTAssertEqual(quote?.price, Decimal(string: "123.45"))
        XCTAssertEqual(quote?.percentChange, Decimal(string: "1.23"))
        XCTAssertEqual(quote?.highestPrice, Decimal(string: "124.00"))
        XCTAssertEqual(quote?.lowestPrice, Decimal(string: "121.00"))
        XCTAssertEqual(quote?.openPrice, Decimal(string: "122.00"))
        XCTAssertEqual(quote?.previousClose, Decimal(string: "121.95"))
    }

    func testQuotesDecodeMovingAveragesFromDailyKline() async throws {
        MockURLProtocol.requestHandler = { request in
            let body: String
            if request.url?.absoluteString.contains("/api/qt/stock/kline/get") == true {
                let klines = (1...20)
                    .map { day in "\"2026-01-\(String(format: "%02d", day)),0,\(day),0,0,0,0,0,0,0,0\"" }
                    .joined(separator: ",")
                body = #"{"data":{"klines":[\#(klines)]}}"#
            } else {
                body = """
                {
                  "data": {
                    "diff": [
                      {
                        "f2": "123.45",
                        "f3": "1.23",
                        "f12": "aapl",
                        "f13": "105",
                        "f14": "Apple",
                        "f15": "124.00",
                        "f16": "122.00",
                        "f17": "121.00",
                        "f18": "121.95",
                        "f232": ""
                      }
                    ]
                  }
                }
                """
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(body.utf8))
        }

        let provider = EastMoneyQuoteProvider(
            session: .mocked,
            afterHoursProvider: nil,
            includesUSAfterHoursSupplement: false
        )
        let symbol = StockSymbol(code: "AAPL", market: .usNASDAQ)

        let quote = try await provider.quotes(for: [symbol])[symbol]

        XCTAssertEqual(quote?.ma5, Decimal(string: "18"))
        XCTAssertEqual(quote?.ma10, Decimal(string: "15.5"))
        XCTAssertEqual(quote?.ma20, Decimal(string: "10.5"))
    }

    func testShouldQueryUSAfterHoursUsesCrossDayRegularSessionInStandardTime() {
        let provider = EastMoneyQuoteProvider(afterHoursProvider: nil)

        XCTAssertFalse(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 1, day: 6, hour: 23, minute: 0)))
        XCTAssertFalse(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 1, day: 7, hour: 4, minute: 30)))
        XCTAssertTrue(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 1, day: 7, hour: 5, minute: 0)))
        XCTAssertTrue(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 1, day: 6, hour: 21, minute: 0)))
    }

    func testShouldQueryUSAfterHoursUsesCrossDayRegularSessionInDaylightSavingTime() {
        let provider = EastMoneyQuoteProvider(afterHoursProvider: nil)

        XCTAssertFalse(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 7, day: 7, hour: 22, minute: 0)))
        XCTAssertFalse(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 7, day: 8, hour: 3, minute: 59)))
        XCTAssertTrue(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 7, day: 8, hour: 4, minute: 0)))
        XCTAssertTrue(provider.shouldQueryUSAfterHours(now: dateInShanghai(year: 2026, month: 7, day: 7, hour: 21, minute: 0)))
    }

    private func dateInShanghai(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let requestHandler = Self.requestHandler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLSession {
    static var mocked: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
