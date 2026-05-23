import Foundation
import XCTest
@testable import StockMonitorNative

final class MonitorRuleEngineTests: XCTestCase {
    func testRuleValidationAcceptsSupportedFormats() {
        let engine = MonitorRuleEngine()
        ["1", "1.25", "3%", "+3%", "-3%", "+1", "-1", "9+", "9-", "|3%", "|+3%", "|-1"].forEach { rawRule in
            XCTAssertTrue(engine.isValid(rule: MonitorRule(rawRule)), rawRule)
        }
    }

    func testRuleValidationRejectsUnsupportedFormats() {
        let engine = MonitorRuleEngine()
        ["", "0", "-0", "abc", "3%%", "3%+", "+9+", "|9+", "|"].forEach { rawRule in
            XCTAssertFalse(engine.isValid(rule: MonitorRule(rawRule)), rawRule)
        }
    }

    func testPriceRangeUsesDecimalMathAndRoundsToTwoPlaces() {
        let range = MonitorRuleEngine().priceRange(
            for: MonitorRule("1.235"),
            previousClose: Decimal(string: "10.00")!,
            costPrice: Decimal(string: "9.00")!
        )

        XCTAssertEqual(range.minimum, Decimal(string: "8.77"))
        XCTAssertEqual(range.maximum, Decimal(string: "11.24"))
    }

    func testPercentagePriceRangeUsesDecimalMathAndRoundsToTwoPlaces() {
        let range = MonitorRuleEngine().priceRange(
            for: MonitorRule("12.345%"),
            previousClose: Decimal(string: "19.99")!,
            costPrice: Decimal(string: "9.00")!
        )

        XCTAssertEqual(range.minimum, Decimal(string: "17.52"))
        XCTAssertEqual(range.maximum, Decimal(string: "22.46"))
    }

    func testReturnToCostUsesDecimalComparison() {
        let config = StockConfig(
            symbol: StockSymbol(code: "AAPL", market: .usNASDAQ),
            costPrice: Decimal(string: "100.01")!,
            position: Decimal(string: "10")!
        )
        let quote = StockQuote(
            symbol: config.symbol,
            name: "Apple",
            price: Decimal(string: "100.02")!,
            percentChange: 0,
            highestPrice: 0,
            openPrice: 0,
            previousClose: Decimal(string: "100.00")!
        )

        XCTAssertTrue(MonitorRuleEngine().shouldTriggerReturnToCost(config: config, quote: quote))
    }
}
