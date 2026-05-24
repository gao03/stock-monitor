import Foundation

public enum LongbridgeRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case cn
    case hk

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto:
            return "自动"
        case .cn:
            return "中国内地"
        case .hk:
            return "香港"
        }
    }
}

public struct LongbridgeQuotePayload: Codable, Equatable, Sendable {
    public var symbol: String
    public var name: String?
    public var lastDone: String?
    public var previousClose: String?
    public var open: String?
    public var high: String?
    public var low: String?
    public var timestamp: Int64?
    public var preMarketQuote: LongbridgeSessionQuotePayload?
    public var postMarketQuote: LongbridgeSessionQuotePayload?
    public var overNightQuote: LongbridgeSessionQuotePayload?

    enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case lastDone = "last_done"
        case previousClose = "prev_close"
        case open
        case high
        case low
        case timestamp
        case preMarketQuote = "pre_market_quote"
        case postMarketQuote = "post_market_quote"
        case overNightQuote = "over_night_quote"
    }

    public init(
        symbol: String,
        name: String? = nil,
        lastDone: String? = nil,
        previousClose: String? = nil,
        open: String? = nil,
        high: String? = nil,
        low: String? = nil,
        timestamp: Int64? = nil,
        preMarketQuote: LongbridgeSessionQuotePayload? = nil,
        postMarketQuote: LongbridgeSessionQuotePayload? = nil,
        overNightQuote: LongbridgeSessionQuotePayload? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.lastDone = lastDone
        self.previousClose = previousClose
        self.open = open
        self.high = high
        self.low = low
        self.timestamp = timestamp
        self.preMarketQuote = preMarketQuote
        self.postMarketQuote = postMarketQuote
        self.overNightQuote = overNightQuote
    }
}

public struct LongbridgeSessionQuotePayload: Codable, Equatable, Sendable {
    public var lastDone: String?
    public var previousClose: String?
    public var high: String?
    public var low: String?
    public var timestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case lastDone = "last_done"
        case previousClose = "prev_close"
        case high
        case low
        case timestamp
    }
}

public struct LongbridgeQuoteSnapshotResponse: Codable, Equatable, Sendable {
    public var quotes: [LongbridgeQuotePayload]
}

enum LongbridgeBridgeEvent: Equatable, Sendable {
    case started
    case ready
    case authorizationRequired(URL)
    case quote(LongbridgeQuotePayload)
    case error(String)
    case sdkPush(JSONValue)
}

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }
}
