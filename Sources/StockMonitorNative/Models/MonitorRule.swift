import Foundation

public struct MonitorRule: Codable, Sendable, Hashable, Identifiable, ExpressibleByStringLiteral {
    public var rawValue: String

    public var id: String { rawValue }
    public var displayText: String { rawValue }

    public init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct MonitorPriceRange: Sendable, Equatable {
    public var minimum: Decimal
    public var maximum: Decimal

    public init(minimum: Decimal, maximum: Decimal) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct MonitorRuleEvaluation: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case priceRule(MonitorRule)
        case returnToCost
    }

    public var kind: Kind
    public var triggered: Bool
    public var currentPrice: Decimal
    public var range: MonitorPriceRange?

    public var id: String {
        switch kind {
        case .priceRule(let rule):
            return rule.rawValue
        case .returnToCost:
            return "回本"
        }
    }

    public init(kind: Kind, triggered: Bool, currentPrice: Decimal, range: MonitorPriceRange? = nil) {
        self.kind = kind
        self.triggered = triggered
        self.currentPrice = currentPrice
        self.range = range
    }
}
