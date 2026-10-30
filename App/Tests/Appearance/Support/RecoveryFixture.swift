import Foundation
@testable import widgets

nonisolated struct RecoveryFixture {
    let suiteName = "AppearanceRecoveryTests." + UUID().uuidString

    init() {}

    func defaults() throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SettingsRecoveryRequestError.unavailablePreferences
        }
        return defaults
    }

    func remove() { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
}

nonisolated struct InterceptedRecoveryRequest: RecoveryRequesting {
    let base: any RecoveryRequesting
    let afterRead: @Sendable () async -> Void

    init(base: any RecoveryRequesting, afterRead: @escaping @Sendable () async -> Void) {
        self.base = base
        self.afterRead = afterRead
    }

    func isRequested() async throws -> Bool {
        let requested = try await base.isRequested()
        await afterRead()
        return requested
    }

    func complete() async throws { try await base.complete() }
}
