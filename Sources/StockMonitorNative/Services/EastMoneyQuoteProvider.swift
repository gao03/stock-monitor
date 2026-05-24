import Foundation

public struct EastMoneyQuoteProvider: StockLookupProvider {
    public var session: URLSession
    public var afterHoursProvider: SinaAfterHoursQuoteProvider?
    public var includesUSAfterHoursSupplement: Bool
    private let dateProvider: @Sendable () -> Date
    private let movingAverageCache = DailyMovingAverageCache()

    public init(
        session: URLSession = .shared,
        afterHoursProvider: SinaAfterHoursQuoteProvider? = SinaAfterHoursQuoteProvider(),
        includesUSAfterHoursSupplement: Bool = true,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.afterHoursProvider = afterHoursProvider
        self.includesUSAfterHoursSupplement = includesUSAfterHoursSupplement
        self.dateProvider = dateProvider
    }

    public func lookupStock(code rawCode: String) async throws -> StockLookupResult? {
        let lookupSymbol = StockSymbol(code: rawCode)
        guard !lookupSymbol.code.isEmpty else { return nil }

        let rows = try await fetchRows(for: [lookupSymbol])
        for row in rows {
            guard let quote = await quote(from: row),
                  normalizedStockCode(quote.symbol.code) == lookupSymbol.code
            else {
                continue
            }

            let stock = StockConfig(symbol: quote.symbol, name: quote.name)
            return StockLookupResult(stock: stock, quote: quote)
        }

        return nil
    }

    public func quotes(for symbols: [StockSymbol]) async throws -> [StockSymbol: StockQuote] {
        let requestedSymbols = symbols.filter { !$0.code.isEmpty }
        guard !requestedSymbols.isEmpty else { return [:] }

        let rows = try await fetchRows(for: requestedSymbols)
        let requestedByCode = Dictionary(grouping: requestedSymbols, by: { normalizedStockCode($0.code) })
        var exactRequests: [StockSymbol: StockSymbol] = [:]
        var codeOnlyRequests: [String: StockSymbol] = [:]
        for symbol in requestedSymbols {
            let normalizedCode = normalizedStockCode(symbol.code)
            if let market = symbol.market {
                let lookupSymbol = StockSymbol(code: normalizedCode, market: market)
                if exactRequests[lookupSymbol] == nil {
                    exactRequests[lookupSymbol] = symbol
                }
            } else {
                if codeOnlyRequests[normalizedCode] == nil {
                    codeOnlyRequests[normalizedCode] = symbol
                }
            }
        }
        var quotes: [StockSymbol: StockQuote] = [:]

        for row in rows {
            guard var quote = await quote(from: row),
                  let market = quote.symbol.market
            else { continue }

            let normalizedCode = normalizedStockCode(quote.symbol.code)
            guard requestedByCode[normalizedCode] != nil else { continue }

            let normalizedSymbol = StockSymbol(code: normalizedCode, market: market)
            if let exactRequest = exactRequests[normalizedSymbol] {
                quote.symbol = exactRequest
                quotes[exactRequest] = quote
            } else if let firstCodeOnlyRequest = codeOnlyRequests[normalizedCode] {
                quote.symbol = firstCodeOnlyRequest
                quotes[firstCodeOnlyRequest] = quote
            } else {
                quotes[quote.symbol] = quote
            }
        }

        return quotes
    }

    private func fetchRows(for symbols: [StockSymbol]) async throws -> [EastMoneyQuoteRow] {
        let secids = symbols.flatMap(\.candidateEastMoneySecIDs).joined(separator: ",")
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/ulist.np/get")
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "f2,f3,f12,f13,f14,f15,f16,f17,f18,f232"),
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "secids", value: secids)
        ]
        guard let url = components?.url else {
            throw QuoteProviderError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard
            let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode
        else {
            throw QuoteProviderError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(EastMoneyAPIResponse.self, from: data)
        return apiResponse.data?.diff ?? []
    }

    private func quote(from row: EastMoneyQuoteRow) async -> StockQuote? {
        guard
            let code = row.code,
            let marketID = row.marketID,
            let market = StockMarket(rawValue: marketID)
        else {
            return nil
        }

        let symbol = StockSymbol(code: code, market: market)
        var quote = StockQuote(
            symbol: symbol,
            name: row.name?.replacingOccurrences(of: " ", with: "") ?? "",
            price: row.price ?? 0,
            percentChange: row.percentChange ?? 0,
            highestPrice: row.highestPrice ?? 0,
            lowestPrice: row.lowestPrice ?? 0,
            openPrice: row.openPrice ?? 0,
            previousClose: row.previousClose ?? 0,
            underlyingStockCode: row.underlyingStockCode,
            timestamp: Date(),
            session: .regular
        )

        if let movingAverages = await movingAverages(for: symbol) {
            quote.ma5 = movingAverages.ma5
            quote.ma10 = movingAverages.ma10
            quote.ma20 = movingAverages.ma20
        }

        if includesUSAfterHoursSupplement,
           market.isUSMarket,
           shouldQueryUSAfterHours(),
           let afterHoursProvider,
           let supplemental = try? await afterHoursProvider.afterHoursQuote(for: symbol) {
            quote.price = supplemental.price
            quote.percentChange = supplemental.percentChange
            quote.timestamp = supplemental.timestamp
            quote.session = .supplemental
        }

        return quote
    }

    public func shouldQueryUSAfterHours(now: Date = Date()) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        guard let chinaTimeZone = TimeZone(identifier: "Asia/Shanghai") else {
            return false
        }
        var chinaCalendar = calendar
        chinaCalendar.timeZone = chinaTimeZone
        let components = chinaCalendar.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute else {
            return false
        }

        let minuteOfDay = hour * 60 + minute
        let regularStart = (isUSDST(now: now) ? 21 : 22) * 60 + 30
        let regularEnd = (isUSDST(now: now) ? 4 : 5) * 60
        return !isMinuteOfDay(minuteOfDay, inCrossDayRangeFrom: regularStart, to: regularEnd)
    }

    private func isUSDST(now: Date) -> Bool {
        TimeZone(identifier: "America/New_York")?.isDaylightSavingTime(for: now) ?? false
    }

    private func movingAverages(for symbol: StockSymbol) async -> MovingAverages? {
        guard let secid = symbol.eastMoneySecID else { return nil }
        let cacheKey = "\(secid)|\(indicatorDateKey())"
        if let entry = await movingAverageCache.entry(for: cacheKey) {
            return entry.value
        }

        do {
            let movingAverages = try await fetchMovingAverages(secid: secid)
            if let movingAverages {
                await movingAverageCache.store(movingAverages, for: cacheKey)
            }
            return movingAverages
        } catch {
            return nil
        }
    }

    private func fetchMovingAverages(secid: String) async throws -> MovingAverages? {
        var components = URLComponents(string: "https://push2his.eastmoney.com/api/qt/stock/kline/get")
        components?.queryItems = [
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61"),
            URLQueryItem(name: "klt", value: "101"),
            URLQueryItem(name: "fqt", value: "1"),
            URLQueryItem(name: "lmt", value: "20"),
            URLQueryItem(name: "end", value: "20500101"),
            URLQueryItem(name: "secid", value: secid)
        ]
        guard let url = components?.url else {
            throw QuoteProviderError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard
            let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode
        else {
            throw QuoteProviderError.invalidResponse
        }

        let apiResponse = try JSONDecoder().decode(EastMoneyKlineAPIResponse.self, from: data)
        let closes = apiResponse.data?.klines.compactMap(closePrice(from:)) ?? []
        guard !closes.isEmpty else { return nil }
        return MovingAverages(
            ma5: movingAverage(closes, days: 5),
            ma10: movingAverage(closes, days: 10),
            ma20: movingAverage(closes, days: 20)
        )
    }

    private func indicatorDateKey() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: dateProvider())
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func closePrice(from kline: String) -> Decimal? {
        let fields = kline.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count > 2 else { return nil }
        return Decimal(string: String(fields[2]), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func movingAverage(_ closes: [Decimal], days: Int) -> Decimal {
        guard closes.count >= days else { return 0 }
        let values = closes.suffix(days)
        let sum = values.reduce(Decimal(0), +)
        return sum / Decimal(days)
    }
}

func normalizedStockCode(_ code: String) -> String {
    code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

func isMinuteOfDay(_ minute: Int, inCrossDayRangeFrom start: Int, to end: Int) -> Bool {
    if start <= end {
        return minute >= start && minute < end
    }
    return minute >= start || minute < end
}

private struct EastMoneyAPIResponse: Decodable {
    var data: EastMoneyAPIData?
}

private struct EastMoneyAPIData: Decodable {
    var diff: [EastMoneyQuoteRow]
}

private struct EastMoneyQuoteRow: Decodable {
    var price: Decimal?
    var percentChange: Decimal?
    var code: String?
    var marketID: Int?
    var name: String?
    var highestPrice: Decimal?
    var lowestPrice: Decimal?
    var openPrice: Decimal?
    var previousClose: Decimal?
    var underlyingStockCode: String?

    enum CodingKeys: String, CodingKey {
        case price = "f2"
        case percentChange = "f3"
        case code = "f12"
        case marketID = "f13"
        case name = "f14"
        case highestPrice = "f15"
        case openPrice = "f16"
        case lowestPrice = "f17"
        case previousClose = "f18"
        case underlyingStockCode = "f232"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        price = try container.decodeFlexibleDecimalIfPresent(forKey: .price)
        percentChange = try container.decodeFlexibleDecimalIfPresent(forKey: .percentChange)
        code = try container.decodeStringIfPresent(forKey: .code)
        marketID = try container.decodeFlexibleIntIfPresent(forKey: .marketID)
        name = try container.decodeStringIfPresent(forKey: .name)
        highestPrice = try container.decodeFlexibleDecimalIfPresent(forKey: .highestPrice)
        lowestPrice = try container.decodeFlexibleDecimalIfPresent(forKey: .lowestPrice)
        openPrice = try container.decodeFlexibleDecimalIfPresent(forKey: .openPrice)
        previousClose = try container.decodeFlexibleDecimalIfPresent(forKey: .previousClose)
        underlyingStockCode = try container.decodeStringIfPresent(forKey: .underlyingStockCode)
    }
}

private struct EastMoneyKlineAPIResponse: Decodable {
    var data: EastMoneyKlineData?
}

private struct EastMoneyKlineData: Decodable {
    var klines: [String]
}

private struct MovingAverages: Sendable {
    var ma5: Decimal
    var ma10: Decimal
    var ma20: Decimal
}

private struct MovingAveragesCacheEntry: Sendable {
    var value: MovingAverages
}

private actor DailyMovingAverageCache {
    private var entries: [String: MovingAveragesCacheEntry] = [:]

    func entry(for key: String) -> MovingAveragesCacheEntry? {
        entries[key]
    }

    func store(_ value: MovingAverages, for key: String) {
        entries[key] = MovingAveragesCacheEntry(value: value)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let decimal = try decodeFlexibleDecimalIfPresent(forKey: key) {
            return NSDecimalNumber(decimal: decimal).intValue
        }
        return nil
    }

    func decodeStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let int = try decodeIfPresent(Int.self, forKey: key) {
            return String(int)
        }
        if let double = try decodeIfPresent(Double.self, forKey: key) {
            return String(double)
        }
        return nil
    }
}
