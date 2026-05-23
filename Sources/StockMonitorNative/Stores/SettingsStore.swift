import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var refreshInterval: TimeInterval
    public var duplicateAlertInterval: TimeInterval
    public var returnToCostAlertInterval: TimeInterval
    public var statusBarTextColorMode: StatusBarTextColorMode
    public var updatedAt: Date

    public init(
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        refreshInterval: TimeInterval = 2,
        duplicateAlertInterval: TimeInterval = 5 * 60,
        returnToCostAlertInterval: TimeInterval = 10 * 60 * 60,
        statusBarTextColorMode: StatusBarTextColorMode = .redUpGreenDown,
        updatedAt: Date = Date()
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.refreshInterval = refreshInterval
        self.duplicateAlertInterval = duplicateAlertInterval
        self.returnToCostAlertInterval = returnToCostAlertInterval
        self.statusBarTextColorMode = statusBarTextColorMode
        self.updatedAt = updatedAt
    }

}

public enum StatusBarTextColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case redUpGreenDown
    case greenUpRedDown
    case black

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .redUpGreenDown:
            return "红涨绿跌"
        case .greenUpRedDown:
            return "绿涨红跌"
        case .black:
            return "黑色"
        }
    }
}

public final class SettingsStore {
    private let store: JSONFileStore<AppSettings>

    public init(store: JSONFileStore<AppSettings>? = nil) {
        if let store {
            self.store = store
        } else {
            self.store = (try? JSONFileStore(fileName: "settings.json", defaultValue: AppSettings())) ?? .temporary(
                fileName: "StockMonitorNative-settings.json",
                defaultValue: AppSettings()
            )
        }
    }

    public func load() -> AppSettings {
        (try? store.load()) ?? AppSettings()
    }

    public func save(_ settings: AppSettings) {
        var settings = settings
        settings.updatedAt = Date()
        try? store.save(settings)
    }

    public func reset() {
        try? store.clear()
    }
}
