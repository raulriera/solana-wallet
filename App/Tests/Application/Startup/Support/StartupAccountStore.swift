import Testing
@testable import widgets

/// Suspends or fails reads while rejecting any startup attempt to write metadata.
struct StartupAccountStore: AccountStoring {
    let read: @Sendable () async throws -> [Account]

    /// Configures the isolated read used by a startup test.
    /// - Parameter read: The operation that returns or rejects public metadata.
    init(read: @escaping @Sendable () async throws -> [Account]) {
        self.read = read
    }

    /// Runs the test's controlled read.
    /// - Returns: Public metadata supplied by the test.
    /// - Throws: The test's scripted error.
    func load() async throws -> [Account] { try await read() }

    /// Reports a regression if startup attempts to modify account storage.
    /// - Parameter account: The unexpected addition.
    /// - Returns: An empty list after recording the test failure.
    func add(_ account: Account) async throws -> [Account] {
        Issue.record("Startup must not write account metadata")
        return []
    }

    /// Reports a regression if startup attempts to delete account storage.
    func removeAll() async throws {
        Issue.record("Startup must not delete account metadata")
    }
}
