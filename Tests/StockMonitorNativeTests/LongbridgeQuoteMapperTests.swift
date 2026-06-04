import XCTest
@testable import StockMonitorNative

final class LongbridgeQuoteMapperTests: XCTestCase {
    func testStockSymbolBuildsLongbridgeSymbol() {
        XCTAssertEqual(StockSymbol(code: "AAPL", market: .usNASDAQ).longbridgeSymbol, "AAPL.US")
        XCTAssertEqual(StockSymbol(code: "700", market: .hongKong).longbridgeSymbol, "700.HK")
        XCTAssertEqual(StockSymbol(code: "00700", market: .hongKong).longbridgeSymbol, "700.HK")
        XCTAssertEqual(StockSymbol(code: "01810", market: .hongKong).longbridgeSymbol, "1810.HK")
        XCTAssertEqual(StockSymbol(code: "000001", market: .shenzhen).longbridgeSymbol, "000001.SZ")
        XCTAssertEqual(StockSymbol(code: "600000", market: .shanghai).longbridgeSymbol, "600000.SH")
    }

    func testLongbridgeSymbolNormalizerHandlesHongKongLeadingZeros() {
        XCTAssertEqual(LongbridgeSymbolNormalizer.normalized("01810.HK"), "1810.HK")
        XCTAssertEqual(LongbridgeSymbolNormalizer.normalized("1810.HK"), "1810.HK")
        XCTAssertEqual(LongbridgeSymbolNormalizer.normalized("AAPL.US"), "AAPL.US")
    }

    func testXueqiuURLUsesFiveDigitHongKongCodeWithoutPrefix() {
        XCTAssertEqual(
            XueqiuURLBuilder.url(for: StockSymbol(code: "01810", market: .hongKong)).absoluteString,
            "https://xueqiu.com/S/01810"
        )
        XCTAssertEqual(
            XueqiuURLBuilder.url(for: StockSymbol(code: "1810", market: .hongKong)).absoluteString,
            "https://xueqiu.com/S/01810"
        )
        XCTAssertEqual(
            XueqiuURLBuilder.url(for: StockSymbol(code: "600000", market: .shanghai)).absoluteString,
            "https://xueqiu.com/S/SH600000"
        )
    }

    func testMapperKeepsDecimalPrecisionFromStringPayload() {
        let stock = StockConfig(
            symbol: StockSymbol(code: "AAPL", market: .usNASDAQ),
            name: "苹果"
        )
        let payload = LongbridgeQuotePayload(
            symbol: "AAPL.US",
            lastDone: "309.455",
            previousClose: "305.000",
            open: "306.000",
            high: "311.400",
            low: "304.800",
            timestamp: 1_770_000_000
        )

        let quote = LongbridgeQuoteMapper().quote(from: payload, stock: stock, existingQuote: nil)

        XCTAssertEqual(quote?.price, Decimal(string: "309.455"))
        XCTAssertEqual(quote?.previousClose, Decimal(string: "305.000"))
        XCTAssertEqual(quote?.openPrice, Decimal(string: "306.000"))
        XCTAssertEqual(quote?.highestPrice, Decimal(string: "311.400"))
        XCTAssertEqual(quote?.lowestPrice, Decimal(string: "304.800"))
        XCTAssertEqual(quote?.session, .streaming)
    }

    func testMapperIgnoresPushWithoutPreviousCloseUntilSnapshotExists() {
        let stock = StockConfig(
            symbol: StockSymbol(code: "AAPL", market: .usNASDAQ),
            name: "苹果"
        )
        let payload = LongbridgeQuotePayload(
            symbol: "AAPL.US",
            lastDone: "309.455",
            open: "306.000",
            high: "311.400",
            low: "304.800",
            timestamp: 1_770_000_000
        )

        let quote = LongbridgeQuoteMapper().quote(from: payload, stock: stock, existingQuote: nil)

        XCTAssertNil(quote)
    }

    func testMapperPrefersRegularQuoteOverStaleSessionQuote() {
        let stock = StockConfig(
            symbol: StockSymbol(code: "AAPL", market: .usNASDAQ),
            name: "苹果"
        )
        let payload = LongbridgeQuotePayload(
            symbol: "AAPL.US",
            lastDone: "309.455",
            previousClose: "305.000",
            open: "306.000",
            high: "311.400",
            low: "304.800",
            timestamp: 1_770_000_000,
            postMarketQuote: LongbridgeSessionQuotePayload(
                lastDone: "330.000",
                previousClose: "305.000",
                high: "333.000",
                low: "329.000",
                timestamp: 1_770_000_001
            )
        )

        let quote = LongbridgeQuoteMapper().quote(from: payload, stock: stock, existingQuote: nil)

        XCTAssertEqual(quote?.price, Decimal(string: "309.455"))
    }
}
