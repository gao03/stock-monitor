import Foundation

public final class StockStore {
    private let store: JSONFileStore<[StockConfig]>
    private let operationStore: OperationStore?

    public init(
        store: JSONFileStore<[StockConfig]>? = nil,
        operationStore: OperationStore? = nil
    ) {
        self.operationStore = operationStore
        if let store {
            self.store = store
        } else {
            self.store = (try? JSONFileStore(fileName: "stocks.json", defaultValue: [])) ?? JSONFileStore.inMemory(defaultValue: [])
        }
    }

    public func load() -> [StockConfig] {
        (try? store.load()) ?? []
    }

    public func save(_ stocks: [StockConfig]) {
        do {
            try store.save(stocks)
        } catch {
            operationStore?.append(type: .custom, description: "保存股票配置失败: \(error.localizedDescription)")
        }
    }
}

private extension JSONFileStore where Value == [StockConfig] {
    static func inMemory(defaultValue: [StockConfig]) -> JSONFileStore<[StockConfig]> {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("StockMonitorNative-stocks.json")
        return JSONFileStore(fileURL: url, defaultValue: defaultValue)
    }
}
