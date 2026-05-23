import Foundation

public enum JSONFileStoreError: Error, Equatable {
    case invalidApplicationSupportDirectory
}

public final class JSONFileStore<Value: Codable & Sendable> {
    private let fileURL: URL
    private let defaultValue: Value
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileName: String,
        defaultValue: Value,
        fileManager: FileManager = .default
    ) throws {
        guard !fileName.isEmpty else {
            throw JSONFileStoreError.invalidApplicationSupportDirectory
        }

        let directoryURL = try ApplicationStorage.applicationSupportDirectory(
            fileManager: fileManager
        )

        self.fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        self.defaultValue = defaultValue
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public init(
        fileURL: URL,
        defaultValue: Value,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.defaultValue = defaultValue
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public var url: URL {
        fileURL
    }

    public func load() throws -> Value {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return defaultValue
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let data = try encoder.encode(value)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    public func clear() throws {
        try save(defaultValue)
    }
}

extension JSONFileStore {
    static func temporary(fileName: String, defaultValue: Value) -> JSONFileStore<Value> {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        return JSONFileStore(fileURL: url, defaultValue: defaultValue)
    }
}
