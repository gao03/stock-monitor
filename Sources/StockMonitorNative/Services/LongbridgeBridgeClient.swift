import Foundation

enum LongbridgeBridgeClientError: Error, LocalizedError {
    case executableNotFound(URL)
    case processNotRunning
    case bridgeError(String)
    case invalidResponse
    case missingEventPayload

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let url):
            return "Longbridge bridge executable was not found at \(url.path)."
        case .processNotRunning:
            return "Longbridge bridge is not running."
        case .bridgeError(let message):
            return message
        case .invalidResponse:
            return "Longbridge bridge returned an invalid response."
        case .missingEventPayload:
            return "Longbridge bridge event payload is missing."
        }
    }
}

actor LongbridgeBridgeClient {
    private let executableURL: URL
    private var process: Process?
    private var processToken: UUID?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readBuffer = Data()
    private var pendingRequests: [String: CheckedContinuation<JSONValue?, Error>] = [:]
    private var eventContinuations: [UUID: AsyncStream<LongbridgeBridgeEvent>.Continuation] = [:]

    init(executableURL: URL = LongbridgeBridgeClient.defaultExecutableURL()) {
        self.executableURL = executableURL
    }

    static func defaultExecutableURL() -> URL {
        if let configuredPath = ProcessInfo.processInfo.environment["STOCK_MONITOR_LONGBRIDGE_BRIDGE"],
           !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: configuredPath)
        }

        if let bundleURL = Bundle.main.url(forResource: "longbridge-bridge", withExtension: nil) {
            return bundleURL
        }

        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            let bundledExecutableURL = executableDirectory.appendingPathComponent("longbridge-bridge")
            if FileManager.default.isExecutableFile(atPath: bundledExecutableURL.path) {
                return bundledExecutableURL
            }
        }

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let sourceRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if let developmentURL = findDevelopmentExecutable(from: sourceRootURL) {
            return developmentURL
        }

        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let developmentURL = findDevelopmentExecutable(from: currentDirectoryURL) {
            return developmentURL
        }

        return currentDirectoryURL.appendingPathComponent("rust/longbridge-bridge/target/debug/longbridge-bridge")
    }

    private static func findDevelopmentExecutable(from startURL: URL) -> URL? {
        var directoryURL = startURL
        for _ in 0..<8 {
            let candidateURL = directoryURL.appendingPathComponent("rust/longbridge-bridge/target/debug/longbridge-bridge")
            if FileManager.default.isExecutableFile(atPath: candidateURL.path) {
                return candidateURL
            }

            let parentURL = directoryURL.deletingLastPathComponent()
            if parentURL.path == directoryURL.path {
                break
            }
            directoryURL = parentURL
        }
        return nil
    }

    func events() -> AsyncStream<LongbridgeBridgeEvent> {
        AsyncStream { continuation in
            let id = UUID()
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeEventContinuation(id: id)
                }
            }
        }
    }

    func configure(
        clientID: String,
        callbackPort: Int = 60355,
        region: LongbridgeRegion,
        language: String = "zh-CN",
        enableOvernight: Bool = false
    ) async throws {
        let params = ConfigureParams(
            clientID: clientID,
            callbackPort: callbackPort,
            region: region,
            language: language,
            enableOvernight: enableOvernight,
            forceReauthorize: false
        )
        _ = try await request(method: "auth.configure", params: params)
    }

    func reauthorize(
        clientID: String,
        callbackPort: Int = 60355,
        region: LongbridgeRegion,
        language: String = "zh-CN",
        enableOvernight: Bool = false
    ) async throws {
        let params = ConfigureParams(
            clientID: clientID,
            callbackPort: callbackPort,
            region: region,
            language: language,
            enableOvernight: enableOvernight,
            forceReauthorize: true
        )
        _ = try await request(method: "auth.reauthorize", params: params)
    }

    func subscribe(symbols: [String]) async throws {
        guard !symbols.isEmpty else { return }
        _ = try await request(method: "quote.subscribe", params: SymbolsParams(symbols: symbols))
    }

    func unsubscribe(symbols: [String]) async throws {
        guard !symbols.isEmpty else { return }
        _ = try await request(method: "quote.unsubscribe", params: SymbolsParams(symbols: symbols))
    }

    func snapshot(symbols: [String]) async throws -> [LongbridgeQuotePayload] {
        guard !symbols.isEmpty else { return [] }
        guard let result = try await request(method: "quote.snapshot", params: SymbolsParams(symbols: symbols)) else {
            throw LongbridgeBridgeClientError.invalidResponse
        }
        return try result.decoded(LongbridgeQuoteSnapshotResponse.self).quotes
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        let processToStop = process
        process = nil
        processToken = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        readBuffer = Data()
        for continuation in pendingRequests.values {
            continuation.resume(throwing: LongbridgeBridgeClientError.processNotRunning)
        }
        pendingRequests.removeAll()
        processToStop?.terminate()
    }

    private func removeEventContinuation(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true {
            return
        }

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw LongbridgeBridgeClientError.executableNotFound(executableURL)
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let processToken = UUID()

        process.executableURL = executableURL
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.consumeStdout(data, processToken: processToken)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                debugPrint("Longbridge bridge stderr: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.handleTermination(processToken: processToken)
            }
        }

        self.process = process
        self.processToken = processToken
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if self.processToken == processToken {
                self.process = nil
                self.processToken = nil
                self.stdinPipe = nil
                self.stdoutPipe = nil
                self.stderrPipe = nil
                self.readBuffer = Data()
            }
            throw error
        }
    }

    private func request<Params: Encodable>(method: String, params: Params) async throws -> JSONValue? {
        try startIfNeeded()
        guard let input = stdinPipe?.fileHandleForWriting else {
            throw LongbridgeBridgeClientError.processNotRunning
        }

        let id = UUID().uuidString
        let command = BridgeCommand(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(command)
        var line = data
        line.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            do {
                try input.write(contentsOf: line)
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func consumeStdout(_ data: Data, processToken: UUID) {
        guard self.processToken == processToken else { return }
        guard !data.isEmpty else {
            handleTermination(processToken: processToken)
            return
        }

        readBuffer.append(data)
        while let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
            let line = readBuffer[..<newlineIndex]
            readBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        do {
            let message = try JSONDecoder().decode(BridgeMessage.self, from: data)
            if let id = message.id {
                handleResponse(message, id: id)
            } else if let event = message.event {
                try handleEvent(event, data: message.data)
            }
        } catch {
            publish(.error("Longbridge bridge decode failed: \(error.localizedDescription)"))
        }
    }

    private func handleResponse(_ message: BridgeMessage, id: String) {
        guard let continuation = pendingRequests.removeValue(forKey: id) else {
            return
        }

        if message.ok == true {
            continuation.resume(returning: message.result)
        } else {
            continuation.resume(throwing: LongbridgeBridgeClientError.bridgeError(message.error ?? "Longbridge bridge request failed."))
        }
    }

    private func handleEvent(_ event: String, data: JSONValue?) throws {
        switch event {
        case "started":
            publish(.started)
        case "ready":
            publish(.ready)
        case "oauth.authorize":
            guard let data,
                  let payload = try? data.decoded(AuthorizePayload.self),
                  let url = URL(string: payload.url)
            else {
                throw LongbridgeBridgeClientError.missingEventPayload
            }
            publish(.authorizationRequired(url))
        case "quote":
            guard let data else {
                throw LongbridgeBridgeClientError.missingEventPayload
            }
            publish(.quote(try data.decoded(LongbridgeQuotePayload.self)))
        case "sdk.push":
            if let data {
                publish(.sdkPush(data))
            }
        case "error":
            let message = (try? data?.decoded(ErrorPayload.self).message) ?? "Longbridge bridge error."
            publish(.error(message))
        default:
            break
        }
    }

    private func publish(_ event: LongbridgeBridgeEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func handleTermination(processToken: UUID) {
        guard self.processToken == processToken else { return }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        self.processToken = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        readBuffer = Data()

        for continuation in pendingRequests.values {
            continuation.resume(throwing: LongbridgeBridgeClientError.processNotRunning)
        }
        pendingRequests.removeAll()
        publish(.error("Longbridge bridge stopped."))
    }
}

private struct ConfigureParams: Encodable {
    var clientID: String
    var callbackPort: Int
    var region: LongbridgeRegion
    var language: String
    var enableOvernight: Bool
    var forceReauthorize: Bool

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case callbackPort = "callback_port"
        case region
        case language
        case enableOvernight = "enable_overnight"
        case forceReauthorize = "force_reauthorize"
    }
}

private struct SymbolsParams: Encodable {
    var symbols: [String]
}

private struct BridgeCommand<Params: Encodable>: Encodable {
    var id: String
    var method: String
    var params: Params
}

private struct BridgeMessage: Decodable {
    var id: String?
    var ok: Bool?
    var result: JSONValue?
    var error: String?
    var event: String?
    var data: JSONValue?
}

private struct AuthorizePayload: Decodable {
    var url: String
}

private struct ErrorPayload: Decodable {
    var message: String
}
