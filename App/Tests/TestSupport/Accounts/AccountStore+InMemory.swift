@testable import widgets

extension AccountStore {
    static func inMemory(_ storage: StoredValue<[Account]> = StoredValue(),
                         cleanup: any RecoveryCleaning = StartupRecoveryCleanup()) -> AccountStore {
        AccountStore(storage: storage, cleanup: cleanup)
    }
}
