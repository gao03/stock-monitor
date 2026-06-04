import Foundation

func normalizedStockCode(_ code: String) -> String {
    code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}

func xueqiuHongKongStockCode(_ code: String) -> String {
    let normalizedCode = normalizedStockCode(code)
    guard isASCIIDigits(normalizedCode), normalizedCode.count < 5 else {
        return normalizedCode
    }
    return String(repeating: "0", count: 5 - normalizedCode.count) + normalizedCode
}

func longbridgeHongKongStockCode(_ code: String) -> String {
    let normalizedCode = normalizedStockCode(code)
    guard isASCIIDigits(normalizedCode) else {
        return normalizedCode
    }

    let strippedCode = normalizedCode.drop { $0 == "0" }
    return strippedCode.isEmpty ? "0" : String(strippedCode)
}

private func isASCIIDigits(_ value: String) -> Bool {
    !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
        scalar.value >= 48 && scalar.value <= 57
    }
}
