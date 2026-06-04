import Foundation

public enum StockMarket: Int, Codable, Sendable, CaseIterable, Hashable {
    case shenzhen = 0
    case shanghai = 1
    case usNASDAQ = 105
    case usNYSE = 106
    case usAMEX = 107
    case hongKong = 116

    public var eastMoneyID: Int { rawValue }

    public var displayName: String {
        switch self {
        case .shenzhen:
            return "深 A"
        case .shanghai:
            return "沪 A"
        case .usNASDAQ:
            return "美股 NASDAQ"
        case .usNYSE:
            return "美股 NYSE"
        case .usAMEX:
            return "美股 AMEX"
        case .hongKong:
            return "港股"
        }
    }

    public var isUSMarket: Bool {
        switch self {
        case .usNASDAQ, .usNYSE, .usAMEX:
            return true
        case .shenzhen, .shanghai, .hongKong:
            return false
        }
    }

    public var isAShareMarket: Bool {
        self == .shenzhen || self == .shanghai
    }

    public var xueqiuPrefix: String {
        switch self {
        case .shenzhen:
            return "SZ"
        case .shanghai:
            return "SH"
        case .hongKong:
            return ""
        case .usNASDAQ, .usNYSE, .usAMEX:
            return ""
        }
    }

    public var shouldShowNow: Bool {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        switch self {
        case .shenzhen, .shanghai:
            return minuteOfDay >= 9 * 60 + 15 && minuteOfDay <= 15 * 60 + 10
        case .hongKong:
            return minuteOfDay >= 9 * 60 && minuteOfDay <= 16 * 60 + 10
        case .usNASDAQ, .usNYSE, .usAMEX:
            return minuteOfDay <= 9 * 60 || minuteOfDay >= 16 * 60
        }
    }

    public static var eastMoneyLookupOrder: [StockMarket] {
        [.shenzhen, .shanghai, .usNASDAQ, .usNYSE, .usAMEX, .hongKong]
    }
}

public struct StockSymbol: Codable, Sendable, Hashable, Identifiable {
    public var code: String
    public var market: StockMarket?

    public var id: String {
        if let market {
            return "\(market.rawValue).\(code)"
        }
        return code
    }

    public var cacheKey: String { id }

    public var displayText: String {
        if let market {
            return "\(code) · \(market.displayName)"
        }
        return code
    }

    public init(code: String, market: StockMarket? = nil) {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.market = market
    }

    enum CodingKeys: String, CodingKey {
        case code
        case market
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(String.self, forKey: .code)
        let market = try container.decodeIfPresent(StockMarket.self, forKey: .market)
        self.init(code: code, market: market)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(market, forKey: .market)
    }

    public var eastMoneySecID: String? {
        guard let market else { return nil }
        return "\(market.eastMoneyID).\(code)"
    }

    public var candidateEastMoneySecIDs: [String] {
        if let eastMoneySecID {
            return [eastMoneySecID]
        }
        return StockMarket.eastMoneyLookupOrder.map { "\($0.eastMoneyID).\(code)" }
    }
}

public struct StockConfig: Codable, Sendable, Identifiable, Hashable {
    public var symbol: StockSymbol
    public var name: String
    public var costPrice: Decimal
    public var position: Decimal
    public var showInTitle: Bool
    public var monitorRules: [MonitorRule]

    public var id: String { symbol.id }

    public init(
        symbol: StockSymbol,
        name: String = "",
        costPrice: Decimal = 0,
        position: Decimal = 0,
        showInTitle: Bool = false,
        monitorRules: [MonitorRule] = []
    ) {
        self.symbol = symbol
        self.name = name
        self.costPrice = costPrice
        self.position = position
        self.showInTitle = showInTitle
        self.monitorRules = monitorRules
    }

    public var displayName: String {
        name.isEmpty ? symbol.code : name
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case costPrice
        case position
        case showInTitle
        case monitorRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(StockSymbol.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        costPrice = try container.decodeFlexibleDecimalIfPresent(forKey: .costPrice) ?? 0
        position = try container.decodeFlexibleDecimalIfPresent(forKey: .position) ?? 0
        showInTitle = try container.decodeIfPresent(Bool.self, forKey: .showInTitle) ?? false
        monitorRules = try container.decodeIfPresent([MonitorRule].self, forKey: .monitorRules) ?? []
    }
}

public struct StockQuote: Codable, Sendable, Identifiable, Hashable {
    public var symbol: StockSymbol
    public var name: String
    public var price: Decimal
    public var percentChange: Decimal
    public var highestPrice: Decimal
    public var lowestPrice: Decimal
    public var openPrice: Decimal
    public var averagePrice: Decimal
    public var previousClose: Decimal
    public var ma5: Decimal
    public var ma10: Decimal
    public var ma20: Decimal
    public var underlyingStockCode: String?
    public var timestamp: Date
    public var session: QuoteSession

    public var id: String { symbol.id }

    public var changePercent: Decimal { percentChange }

    public init(
        symbol: StockSymbol,
        name: String,
        price: Decimal,
        percentChange: Decimal,
        highestPrice: Decimal,
        lowestPrice: Decimal = 0,
        openPrice: Decimal,
        averagePrice: Decimal = 0,
        previousClose: Decimal,
        ma5: Decimal = 0,
        ma10: Decimal = 0,
        ma20: Decimal = 0,
        underlyingStockCode: String? = nil,
        timestamp: Date = Date(),
        session: QuoteSession = .regular
    ) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.percentChange = percentChange
        self.highestPrice = highestPrice
        self.lowestPrice = lowestPrice
        self.openPrice = openPrice
        self.averagePrice = averagePrice
        self.previousClose = previousClose
        self.ma5 = ma5
        self.ma10 = ma10
        self.ma20 = ma20
        self.underlyingStockCode = underlyingStockCode
        self.timestamp = timestamp
        self.session = session
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case price
        case percentChange
        case highestPrice
        case lowestPrice
        case openPrice
        case averagePrice
        case previousClose
        case ma5
        case ma10
        case ma20
        case underlyingStockCode
        case timestamp
        case session
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(StockSymbol.self, forKey: .symbol)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decodeFlexibleDecimal(forKey: .price)
        percentChange = try container.decodeFlexibleDecimal(forKey: .percentChange)
        highestPrice = try container.decodeFlexibleDecimal(forKey: .highestPrice)
        lowestPrice = try container.decodeFlexibleDecimalIfPresent(forKey: .lowestPrice) ?? 0
        openPrice = try container.decodeFlexibleDecimal(forKey: .openPrice)
        averagePrice = try container.decodeFlexibleDecimalIfPresent(forKey: .averagePrice) ?? 0
        previousClose = try container.decodeFlexibleDecimal(forKey: .previousClose)
        ma5 = try container.decodeFlexibleDecimalIfPresent(forKey: .ma5) ?? 0
        ma10 = try container.decodeFlexibleDecimalIfPresent(forKey: .ma10) ?? 0
        ma20 = try container.decodeFlexibleDecimalIfPresent(forKey: .ma20) ?? 0
        underlyingStockCode = try container.decodeIfPresent(String.self, forKey: .underlyingStockCode)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        session = try container.decodeIfPresent(QuoteSession.self, forKey: .session) ?? .regular
    }
}

public enum QuoteSession: String, Codable, Sendable, Hashable {
    case regular
    case preMarket
    case afterHours
    case supplemental
    case streaming
}

public struct AfterHoursQuote: Codable, Sendable, Hashable {
    public var symbol: StockSymbol
    public var price: Decimal
    public var percentChange: Decimal
    public var timestamp: Date

    public init(symbol: StockSymbol, price: Decimal, percentChange: Decimal, timestamp: Date = Date()) {
        self.symbol = symbol
        self.price = price
        self.percentChange = percentChange
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case symbol
        case price
        case percentChange
        case timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(StockSymbol.self, forKey: .symbol)
        price = try container.decodeFlexibleDecimal(forKey: .price)
        percentChange = try container.decodeFlexibleDecimal(forKey: .percentChange)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleDecimal(forKey key: Key) throws -> Decimal {
        if let value = try decodeFlexibleDecimalIfPresent(forKey: key) {
            return value
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected Decimal number or string")
    }

    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let value = try? decodeIfPresent(Decimal.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Decimal(string: string.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }
}
