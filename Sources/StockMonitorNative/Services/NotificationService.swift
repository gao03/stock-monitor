import AppKit
import Foundation
import UserNotifications

public struct StockNotification: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var url: URL?

    public init(
        identifier: String = UUID().uuidString,
        title: String,
        subtitle: String = "",
        body: String,
        url: URL? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.url = url
    }
}

public final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center: UNUserNotificationCenter?
    private let settingsStore: SettingsStore

    public init(
        settingsStore: SettingsStore,
        center: UNUserNotificationCenter? = nil
    ) {
        self.settingsStore = settingsStore
        if let center {
            self.center = center
        } else if Bundle.main.bundleIdentifier != nil {
            self.center = .current()
        } else {
            self.center = nil
        }
        super.init()
        self.center?.delegate = self
    }

    public func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func notify(title: String, subtitle: String, body: String, url: URL?) {
        let notification = StockNotification(
            title: title,
            subtitle: subtitle,
            body: body,
            url: url
        )
        deliver(notification)
    }

    public func deliver(_ notification: StockNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        if settingsStore.load().soundEnabled {
            content.sound = .default
        }

        if let url = notification.url {
            content.userInfo["url"] = url.absoluteString
        }

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        center?.add(request)
    }

    public func removeAllDeliveredNotifications() {
        center?.removeAllDeliveredNotifications()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let rawURL = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
