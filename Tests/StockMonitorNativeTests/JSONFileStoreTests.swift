import Foundation
import XCTest
@testable import StockMonitorNative

final class JSONFileStoreTests: XCTestCase {
    func testSaveCreatesParentDirectoryForExplicitFileURL() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("settings.json")
        defer {
            try? FileManager.default.removeItem(at: directoryURL.deletingLastPathComponent())
        }

        let store = JSONFileStore(fileURL: fileURL, defaultValue: AppSettings())
        let settings = AppSettings(refreshInterval: 7)

        try store.save(settings)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try store.load().refreshInterval, 7)
    }

    func testAppSettingsDecodeStatusBarTextColorMode() throws {
        let json = """
        {
          "notificationsEnabled": true,
          "soundEnabled": true,
          "refreshInterval": 2,
          "duplicateAlertInterval": 300,
          "returnToCostAlertInterval": 36000,
          "statusBarTextColorMode": "black",
          "longbridgeEnabled": true,
          "longbridgeClientID": "client-id",
          "longbridgeRegion": "cn",
          "longbridgeEnableOvernight": true,
          "updatedAt": 0
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.statusBarTextColorMode, .black)
        XCTAssertEqual(settings.notificationsEnabled, true)
        XCTAssertEqual(settings.longbridgeClientID, "client-id")
        XCTAssertEqual(settings.longbridgeRegion, .cn)
        XCTAssertTrue(settings.longbridgeEnableOvernight)
    }

    func testStatusBarTextColorOptions() {
        XCTAssertEqual(
            StatusBarTextColorMode.allCases.map(\.displayName),
            ["红涨绿跌", "白色", "黑色"]
        )
    }
}
