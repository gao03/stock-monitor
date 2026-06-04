import Foundation

extension StockSymbol {
    public var longbridgeSymbol: String? {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedCode.isEmpty else { return nil }

        if normalizedCode.contains(".") {
            return LongbridgeSymbolNormalizer.normalized(normalizedCode)
        }

        guard let market else { return nil }
        switch market {
        case .shenzhen:
            return "\(normalizedCode).SZ"
        case .shanghai:
            return "\(normalizedCode).SH"
        case .hongKong:
            return "\(longbridgeHongKongStockCode(normalizedCode)).HK"
        case .usNASDAQ, .usNYSE, .usAMEX:
            return "\(normalizedCode).US"
        }
    }
}

enum LongbridgeSymbolNormalizer {
    static func normalized(_ symbol: String) -> String {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedSymbol.hasSuffix(".HK") else {
            return normalizedSymbol
        }

        let code = String(normalizedSymbol.dropLast(3))
        return "\(longbridgeHongKongStockCode(code)).HK"
    }
}

struct LongbridgeQuoteMapper {
    func quote(
        from payload: LongbridgeQuotePayload,
        stock: StockConfig,
        existingQuote: StockQuote?
    ) -> StockQuote? {
        let effectivePayload = payload.hasLastDone ? payload : payload.preferredSessionPayload ?? payload
        guard let price = decimal(effectivePayload.lastDone ?? payload.lastDone) else {
            return nil
        }

        guard let previousClose = decimal(effectivePayload.previousClose ?? payload.previousClose)
            ?? existingQuote?.previousClose,
              previousClose > 0
        else {
            return nil
        }
        let openPrice = decimal(payload.open) ?? existingQuote?.openPrice ?? 0
        let highestPrice = decimal(effectivePayload.high ?? payload.high) ?? existingQuote?.highestPrice ?? 0
        let lowestPrice = decimal(effectivePayload.low ?? payload.low) ?? existingQuote?.lowestPrice ?? 0
        let timestamp = Date(timeIntervalSince1970: TimeInterval(effectivePayload.timestamp ?? payload.timestamp ?? Int64(Date().timeIntervalSince1970)))
        let percentChange = previousClose == 0 ? 0 : ((price - previousClose) / previousClose) * 100

        var quote = StockQuote(
            symbol: stock.symbol,
            name: payload.name?.isEmpty == false ? payload.name! : stock.displayName,
            price: price,
            percentChange: percentChange,
            highestPrice: highestPrice,
            lowestPrice: lowestPrice,
            openPrice: openPrice,
            averagePrice: existingQuote?.averagePrice ?? 0,
            previousClose: previousClose,
            ma5: existingQuote?.ma5 ?? 0,
            ma10: existingQuote?.ma10 ?? 0,
            ma20: existingQuote?.ma20 ?? 0,
            timestamp: timestamp,
            session: .streaming
        )

        if quote.highestPrice == 0 {
            quote.highestPrice = max(price, quote.openPrice)
        }
        if quote.lowestPrice == 0 {
            quote.lowestPrice = min(price, quote.openPrice == 0 ? price : quote.openPrice)
        }
        return quote
    }

    private func decimal(_ rawValue: String?) -> Decimal? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "--" else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}

private extension LongbridgeQuotePayload {
    var hasLastDone: Bool {
        lastDone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var preferredSessionPayload: LongbridgeQuotePayload? {
        if let overNightQuote, overNightQuote.lastDone?.isEmpty == false {
            return LongbridgeQuotePayload(
                symbol: symbol,
                name: name,
                lastDone: overNightQuote.lastDone,
                previousClose: overNightQuote.previousClose,
                high: overNightQuote.high,
                low: overNightQuote.low,
                timestamp: overNightQuote.timestamp
            )
        }
        if let postMarketQuote, postMarketQuote.lastDone?.isEmpty == false {
            return LongbridgeQuotePayload(
                symbol: symbol,
                name: name,
                lastDone: postMarketQuote.lastDone,
                previousClose: postMarketQuote.previousClose,
                high: postMarketQuote.high,
                low: postMarketQuote.low,
                timestamp: postMarketQuote.timestamp
            )
        }
        if let preMarketQuote, preMarketQuote.lastDone?.isEmpty == false {
            return LongbridgeQuotePayload(
                symbol: symbol,
                name: name,
                lastDone: preMarketQuote.lastDone,
                previousClose: preMarketQuote.previousClose,
                high: preMarketQuote.high,
                low: preMarketQuote.low,
                timestamp: preMarketQuote.timestamp
            )
        }
        return nil
    }
}
