import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var notificationsEnabled: Bool
    public var soundEnabled: Bool
    public var refreshInterval: TimeInterval
    public var duplicateAlertInterval: TimeInterval
    public var returnToCostAlertInterval: TimeInterval
    public var updatedAt: Date

    public init(
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        refreshInterval: TimeInterval = 2,
        duplicateAlertInterval: TimeInterval = 5 * 60,
        returnToCostAlertInterval: TimeInterval = 10 * 60 * 60,
        updatedAt: Date = Date()
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.refreshInterval = refreshInterval
        self.duplicateAlertInterval = duplicateAlertInterval
        self.returnToCostAlertInterval = returnToCostAlertInterval
        self.updatedAt = updatedAt
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
