import Foundation

public enum ApplicationStorage {
    public static let directoryName = "StockMonitorNative"

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directoryURL = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }
}

