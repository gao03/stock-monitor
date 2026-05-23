import Foundation

public struct MonitorRuleEngine: Sendable {
    public init() {}

    public func isValid(rule: MonitorRule) -> Bool {
        parse(rule) != nil
    }

    public func priceRange(
        for rule: MonitorRule,
        previousClose: Decimal,
        costPrice: Decimal
    ) -> MonitorPriceRange {
        guard let parsed = parse(rule) else {
            return MonitorPriceRange(minimum: .monitorLowerBound, maximum: .monitorUpperBound)
        }

        if parsed.isAbsolutePrice {
            if parsed.absolutePriceMeansIncrease {
                return MonitorPriceRange(minimum: .monitorLowerBound, maximum: parsed.monitorValue)
            }
            return MonitorPriceRange(minimum: parsed.monitorValue, maximum: .monitorUpperBound)
        }

        let basePrice = parsed.relativeToCost ? costPrice : previousClose
        let rawMinimum: Decimal
        let rawMaximum: Decimal
        if parsed.isPercentage {
            rawMinimum = basePrice * (1 - parsed.monitorValue / 100)
            rawMaximum = basePrice * (1 + parsed.monitorValue / 100)
        } else {
            rawMinimum = basePrice - parsed.monitorValue
            rawMaximum = basePrice + parsed.monitorValue
        }

        var minimum = rawMinimum.rounded(scale: 2)
        var maximum = rawMaximum.rounded(scale: 2)

        if parsed.onlyIncrease {
            minimum = .monitorLowerBound
        }
        if parsed.onlyDecrease {
            maximum = .monitorUpperBound
        }

        return MonitorPriceRange(minimum: minimum, maximum: maximum)
    }

    public func isTriggered(
        rule: MonitorRule,
        previousClose: Decimal,
        costPrice: Decimal,
        currentPrice: Decimal
    ) -> Bool {
        let range = priceRange(for: rule, previousClose: previousClose, costPrice: costPrice)
        return currentPrice < range.minimum || currentPrice > range.maximum
    }

    public func evaluate(config: StockConfig, quote: StockQuote) -> [MonitorRuleEvaluation] {
        var evaluations = config.monitorRules.map { rule -> MonitorRuleEvaluation in
            let range = priceRange(
                for: rule,
                previousClose: quote.previousClose,
                costPrice: config.costPrice
            )
            let triggered = quote.price < range.minimum || quote.price > range.maximum
            return MonitorRuleEvaluation(
                kind: .priceRule(rule),
                triggered: triggered,
                currentPrice: quote.price,
                range: range
            )
        }

        let returnToCostTriggered = shouldTriggerReturnToCost(config: config, quote: quote)
        evaluations.append(
            MonitorRuleEvaluation(
                kind: .returnToCost,
                triggered: returnToCostTriggered,
                currentPrice: quote.price
            )
        )
        return evaluations
    }

    public func triggeredEvaluations(config: StockConfig, quote: StockQuote) -> [MonitorRuleEvaluation] {
        evaluate(config: config, quote: quote).filter(\.triggered)
    }

    public func shouldTriggerReturnToCost(config: StockConfig, quote: StockQuote) -> Bool {
        config.position > 0 &&
            config.costPrice > quote.previousClose &&
            config.costPrice < quote.price
    }

    private func parse(_ rule: MonitorRule) -> ParsedRule? {
        var text = rule.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var relativeToCost = false
        var onlyIncrease = false
        var onlyDecrease = false
        var isPercentage = false
        var isAbsolutePrice = false
        var absolutePriceMeansIncrease = true

        guard !text.isEmpty else { return nil }

        if text.hasPrefix("|") {
            relativeToCost = true
            text.removeFirst()
            guard !text.isEmpty else { return nil }
        }

        if text.hasPrefix("+") {
            onlyIncrease = true
            text.removeFirst()
            guard !text.isEmpty else { return nil }
        } else if text.hasPrefix("-") {
            onlyDecrease = true
            text.removeFirst()
            guard !text.isEmpty else { return nil }
        }

        if text.hasSuffix("%") {
            isPercentage = true
            text.removeLast()
            guard !text.isEmpty else { return nil }
        }

        if text.hasSuffix("+") || text.hasSuffix("-") {
            isAbsolutePrice = true
            absolutePriceMeansIncrease = text.hasSuffix("+")
            text.removeLast()
            guard !text.isEmpty else { return nil }
        }

        guard !isPercentage || !isAbsolutePrice else { return nil }
        guard !isAbsolutePrice || (!relativeToCost && !onlyIncrease && !onlyDecrease) else { return nil }
        guard text.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil else {
            return nil
        }
        guard let monitorValue = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), monitorValue > 0 else {
            return nil
        }

        return ParsedRule(
            relativeToCost: relativeToCost,
            onlyIncrease: onlyIncrease,
            onlyDecrease: onlyDecrease,
            isPercentage: isPercentage,
            isAbsolutePrice: isAbsolutePrice,
            absolutePriceMeansIncrease: absolutePriceMeansIncrease,
            monitorValue: monitorValue
        )
    }

    private struct ParsedRule {
        var relativeToCost: Bool
        var onlyIncrease: Bool
        var onlyDecrease: Bool
        var isPercentage: Bool
        var isAbsolutePrice: Bool
        var absolutePriceMeansIncrease: Bool
        var monitorValue: Decimal
    }
}

private extension Decimal {
    static let monitorLowerBound = Decimal(string: "0.0000000000000000000000000001", locale: Locale(identifier: "en_US_POSIX"))!
    static let monitorUpperBound = Decimal(string: "9999999999999999999999999999", locale: Locale(identifier: "en_US_POSIX"))!

    func rounded(scale: Int) -> Decimal {
        var input = self
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }
}
