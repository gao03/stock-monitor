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
}
