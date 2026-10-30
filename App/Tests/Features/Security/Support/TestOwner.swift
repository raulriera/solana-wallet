@testable import widgets

actor TestOwner: OwnerAuthenticating {
    private let error: (any Error)?
    private(set) var prompts = 0

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func confirmOwner(reason: String) async throws {
        prompts += 1
        if let error { throw error }
    }
}
