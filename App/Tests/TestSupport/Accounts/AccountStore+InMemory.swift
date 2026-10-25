@testable import widgets

extension AccountStore {
    /// Creates the shared accounts over in-memory storage, without reading it.
    /// - Parameters:
    ///   - storage: The in-memory storage that keeps the accounts.
    ///   - cleanup: The launch cleanup, which completes at once unless a test scripts it.
    /// - Returns: A store that reads nothing until it loads.
    static func inMemory(_ storage: StoredValue<[Account]> = StoredValue(),
                         cleanup: any RecoveryCleaning = StartupRecoveryCleanup()) -> AccountStore {
        AccountStore(storage: storage, cleanup: cleanup)
    }
}
