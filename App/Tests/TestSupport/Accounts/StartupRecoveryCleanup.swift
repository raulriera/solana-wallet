import Testing
@testable import widgets

actor StartupRecoveryCleanup {
    private let error: (any Error)?
    private let gate: Suspension?
    private(set) var completions = 0

    init(error: (any Error)? = nil, gate: Suspension? = nil) {
        self.error = error
        self.gate = gate
    }

    func complete() async throws {
        completions += 1
        await gate?.suspend()
        if let error { throw error }
    }
}

extension StartupRecoveryCleanup: RecoveryCleaning {}
