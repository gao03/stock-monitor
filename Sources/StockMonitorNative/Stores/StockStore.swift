import Foundation

public final class StockStore {
    private let store: JSONFileStore<[StockConfig]>

    public init(store: JSONFileStore<[StockConfig]>? = nil) {
        if let store {
            self.store = store
        } else {
            self.store = (try? JSONFileStore(fileName: "stocks.json", defaultValue: [])) ?? .temporary(
                fileName: "StockMonitorNative-stocks.json",
                defaultValue: []
            )
        }
    }

    public func load() -> [StockConfig] {
        (try? store.load()) ?? []
    }

    public func save(_ stocks: [StockConfig]) {
        try? store.save(stocks)
    }
}
