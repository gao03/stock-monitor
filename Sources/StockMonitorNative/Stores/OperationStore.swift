import Foundation

public enum OperationType: String, Codable, CaseIterable, Sendable {
    case addStock = "add_stock"
    case removeStock = "remove_stock"
    case addMonitor = "add_monitor"
    case removeMonitor = "remove_monitor"
    case updateConfig = "update_config"
    case notification = "notification"
    case settings = "settings"
    case credential = "credential"
    case system = "system"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .addStock:
            return "添加股票"
        case .removeStock:
            return "删除股票"
        case .addMonitor:
            return "添加监控"
        case .removeMonitor:
            return "删除监控"
        case .updateConfig:
            return "更新配置"
        case .notification:
            return "通知"
        case .settings:
            return "设置"
        case .credential:
            return "凭证"
        case .system:
            return "系统"
        case .custom:
            return "自定义"
        }
    }
}

public struct OperationRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var type: OperationType
    public var stockCode: String?
    public var stockName: String?
    public var detail: String
    public var time: Date

    public init(
        id: UUID = UUID(),
        type: OperationType,
        stockCode: String? = nil,
        stockName: String? = nil,
        detail: String,
        time: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.stockCode = stockCode
        self.stockName = stockName
        self.detail = detail
        self.time = time
    }
}

public final class OperationStore {
    private let store: JSONFileStore<[OperationRecord]>

    public init(store: JSONFileStore<[OperationRecord]>? = nil) {
        if let store {
            self.store = store
        } else {
            self.store = (try? JSONFileStore(fileName: "operations.json", defaultValue: [])) ?? JSONFileStore(
                fileURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("StockMonitorNative-operations.json"),
                defaultValue: []
            )
        }
    }

    public func append(_ record: OperationRecord) {
        var records = list()
        records.append(record)
        try? store.save(records)
    }

    @discardableResult
    public func append(
        type: OperationType,
        stockCode: String? = nil,
        stockName: String? = nil,
        description: String,
        time: Date = Date()
    ) -> OperationRecord {
        let record = OperationRecord(
            type: type,
            stockCode: stockCode,
            stockName: stockName,
            detail: description,
            time: time
        )
        append(record)
        return record
    }

    public func list(limit: Int? = nil) -> [OperationRecord] {
        let records = ((try? store.load()) ?? []).sorted { $0.time > $1.time }
        guard let limit else { return records }
        return Array(records.prefix(limit))
    }

    public func clear() {
        try? store.clear()
    }
}
