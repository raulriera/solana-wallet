import Foundation
@testable import widgets

/// Isolates system-preference requests from the app's real Settings domain.
nonisolated struct RecoveryFixture {
    let suiteName = "AppearanceRecoveryTests." + UUID().uuidString

    /// Creates a unique defaults domain for one recovery test.
    init() {}

    /// Reads or writes the same domain used by the real request service.
    /// - Returns: The isolated defaults object.
    /// - Throws: An unavailable-domain error.
    func defaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SettingsRecoveryRequest.Failure.unavailablePreferences
        }
        return defaults
    }

    /// Removes only the defaults domain owned by this test.
    func remove() { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
}

/// Delays a real Settings read to exercise concurrent scene activations deterministically.
nonisolated struct InterceptedRecoveryRequest: RecoveryRequesting {
    let base: any RecoveryRequesting
    let afterRead: @Sendable () async -> Void

    /// Wraps real preferences with an awaitable read barrier.
    /// - Parameters:
    ///   - base: The request service using an isolated defaults domain.
    ///   - afterRead: The test's synchronization point.
    init(base: any RecoveryRequesting, afterRead: @escaping @Sendable () async -> Void) {
        self.base = base
        self.afterRead = afterRead
    }

    /// Reads the real flag and delays delivery to the coordinator.
    /// - Returns: The flag observed before the barrier.
    /// - Throws: A preferences error.
    func isRequested() async throws -> Bool {
        let requested = try await base.isRequested()
        await afterRead()
        return requested
    }

    /// Acknowledges the actual request without intercepting the write.
    /// - Throws: A preferences error.
    func complete() async throws { try await base.complete() }
}
