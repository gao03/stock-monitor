import Foundation

public struct SinaAfterHoursQuoteProvider: Sendable {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func afterHoursQuote(for symbol: StockSymbol) async throws -> AfterHoursQuote? {
        guard symbol.market?.isUSMarket == true else {
            return nil
        }

        var components = URLComponents(string: "https://hq.sinajs.cn/rn")
        components?.queryItems = [
            URLQueryItem(name: "list", value: "gb_\(symbol.code.lowercased())")
        ]
        guard let url = components?.url else {
            throw QuoteProviderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("https://sina.com.cn", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode
        else {
            throw QuoteProviderError.invalidResponse
        }
        guard let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .gb18030) else {
            throw QuoteProviderError.decodingFailed
        }

        return parseAfterHoursQuote(body: body, symbol: symbol)
    }

    public func parseAfterHoursQuote(body: String, symbol: StockSymbol) -> AfterHoursQuote? {
        guard
            let start = body.firstIndex(of: "\""),
            let end = body[body.index(after: start)...].firstIndex(of: "\"")
        else {
            return nil
        }

        let payload = String(body[body.index(after: start)..<end])
        let fields = payload.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count > 22 else {
            return nil
        }

        let price = Decimal(string: fields[21].trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
        let percentChange = Decimal(string: fields[22].trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
        guard let price, let percentChange else {
            return nil
        }

        return AfterHoursQuote(symbol: symbol, price: price, percentChange: percentChange)
    }
}

private extension String.Encoding {
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
}
