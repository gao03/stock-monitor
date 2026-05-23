import Foundation

public enum NumberFormat {
    public static func price(_ value: Decimal) -> String {
        var rounded = value
        var output = Decimal()
        NSDecimalRound(&output, &rounded, 3, .plain)
        var text = NSDecimalNumber(decimal: output).stringValue

        if text.contains(".") {
            while text.last == "0" {
                text.removeLast()
            }
            if text.last == "." {
                text.append("00")
            } else if let fraction = text.split(separator: ".", omittingEmptySubsequences: false).last,
                      fraction.count == 1 {
                text.append("0")
            }
        } else {
            text.append(".00")
        }
        return text
    }

    public static func percent(_ value: Decimal) -> String {
        var rounded = value
        var output = Decimal()
        NSDecimalRound(&output, &rounded, 2, .plain)
        let text = NSDecimalNumber(decimal: output).stringValue
        if text.contains(".") {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            let fractionCount = parts.count > 1 ? parts[1].count : 0
            if fractionCount == 0 { return "\(text)00" }
            if fractionCount == 1 { return "\(text)0" }
            return text
        }
        return "\(text).00"
    }

}

public extension Decimal {
    var formattedPrice: String {
        NumberFormat.price(self)
    }

    var formattedPercent: String {
        "\(NumberFormat.percent(self))%"
    }

    var plainString: String {
        NSDecimalNumber(decimal: self).stringValue
    }

    var signum: Int {
        if self > 0 { return 1 }
        if self < 0 { return -1 }
        return 0
    }
}

public enum XueqiuURLBuilder {
    public static func url(for symbol: StockSymbol) -> URL {
        let prefix = symbol.market?.xueqiuPrefix ?? ""
        return URL(string: "https://xueqiu.com/S/\(prefix)\(symbol.code)")!
    }
}
