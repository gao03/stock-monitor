import Foundation
import XCTest
@testable import StockMonitorNative

final class DecimalModelTests: XCTestCase {
    func testStockSymbolDecodeNormalizesCode() throws {
        let data = Data("""
        {
          "code": " aapl ",
          "market": 105
        }
        """.utf8)

        let symbol = try JSONDecoder().decode(StockSymbol.self, from: data)

        XCTAssertEqual(symbol.code, "AAPL")
        XCTAssertEqual(symbol.market, .usNASDAQ)
    }

    func testStockQuoteDecodesDecimalFieldsFromNumbersAndStrings() throws {
        let data = Data("""
        {
          "symbol": { "code": "AAPL", "market": 105 },
          "name": "Apple",
          "price": "123.45",
          "percentChange": 1.23,
          "highestPrice": "124.00",
          "lowestPrice": "121.00",
          "openPrice": 122.00,
          "averagePrice": "123.00",
          "previousClose": "121.95",
          "ma5": "120.10",
          "ma10": 119.20,
          "ma20": "118.30",
          "session": "regular"
        }
        """.utf8)

        let quote = try JSONDecoder().decode(StockQuote.self, from: data)

        XCTAssertEqual(quote.price, Decimal(string: "123.45"))
        XCTAssertEqual(quote.percentChange, Decimal(string: "1.23"))
        XCTAssertEqual(quote.highestPrice, Decimal(string: "124.00"))
        XCTAssertEqual(quote.lowestPrice, Decimal(string: "121.00"))
        XCTAssertEqual(quote.openPrice, Decimal(string: "122.00"))
        XCTAssertEqual(quote.averagePrice, Decimal(string: "123.00"))
        XCTAssertEqual(quote.previousClose, Decimal(string: "121.95"))
        XCTAssertEqual(quote.ma5, Decimal(string: "120.10"))
        XCTAssertEqual(quote.ma10, Decimal(string: "119.20"))
        XCTAssertEqual(quote.ma20, Decimal(string: "118.30"))
    }

    func testStockConfigDecodesDecimalFieldsFromNumbersAndStrings() throws {
        let data = Data("""
        {
          "symbol": { "code": "AAPL", "market": 105 },
          "name": "Apple",
          "costPrice": "100.10",
          "position": 12.5
        }
        """.utf8)

        let config = try JSONDecoder().decode(StockConfig.self, from: data)

        XCTAssertEqual(config.costPrice, Decimal(string: "100.10"))
        XCTAssertEqual(config.position, Decimal(string: "12.5"))
    }

    func testAfterHoursQuoteDecodesDecimalFieldsFromNumbersAndStrings() throws {
        let data = Data("""
        {
          "symbol": { "code": "AAPL", "market": 105 },
          "price": "123.45",
          "percentChange": 1.23
        }
        """.utf8)

        let quote = try JSONDecoder().decode(AfterHoursQuote.self, from: data)

        XCTAssertEqual(quote.price, Decimal(string: "123.45"))
        XCTAssertEqual(quote.percentChange, Decimal(string: "1.23"))
    }
}
