import Foundation

public enum CredentialStoreError: Error, Equatable {
    case notImplemented
}

public struct Credential: Codable, Equatable, Sendable {
    public var account: String
    public var secret: String

    public init(account: String, secret: String) {
        self.account = account
        self.secret = secret
    }
}

public protocol CredentialStoring: Sendable {
    func save(_ credential: Credential, for service: String) async throws
    func credential(for service: String) async throws -> Credential?
    func deleteCredential(for service: String) async throws
}

public struct PlaceholderCredentialStore: CredentialStoring {
    public init() {}

    public func save(_ credential: Credential, for service: String) async throws {
        throw CredentialStoreError.notImplemented
    }

    public func credential(for service: String) async throws -> Credential? {
        throw CredentialStoreError.notImplemented
    }

    public func deleteCredential(for service: String) async throws {
        throw CredentialStoreError.notImplemented
    }
}

