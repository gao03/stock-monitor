import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var refreshInterval: TimeInterval
    public var duplicateAlertInterval: TimeInterval
    public var returnToCostAlertInterval: TimeInterval
    public var statusBarTextColorMode: StatusBarTextColorMode
    public var longbridgeEnabled: Bool
    public var longbridgeClientID: String
    public var longbridgeRegion: LongbridgeRegion
    public var longbridgeEnableOvernight: Bool
    public var updatedAt: Date

    public init(
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        refreshInterval: TimeInterval = 2,
        duplicateAlertInterval: TimeInterval = 5 * 60,
        returnToCostAlertInterval: TimeInterval = 10 * 60 * 60,
        statusBarTextColorMode: StatusBarTextColorMode = .redUpGreenDown,
        longbridgeEnabled: Bool = false,
        longbridgeClientID: String = "",
        longbridgeRegion: LongbridgeRegion = .auto,
        longbridgeEnableOvernight: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.refreshInterval = refreshInterval
        self.duplicateAlertInterval = duplicateAlertInterval
        self.returnToCostAlertInterval = returnToCostAlertInterval
        self.statusBarTextColorMode = statusBarTextColorMode
        self.longbridgeEnabled = longbridgeEnabled
        self.longbridgeClientID = longbridgeClientID
        self.longbridgeRegion = longbridgeRegion
        self.longbridgeEnableOvernight = longbridgeEnableOvernight
        self.updatedAt = updatedAt
    }
}

public enum StatusBarTextColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case redUpGreenDown
    case white
    case black

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .redUpGreenDown:
            return "红涨绿跌"
        case .white:
            return "白色"
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
