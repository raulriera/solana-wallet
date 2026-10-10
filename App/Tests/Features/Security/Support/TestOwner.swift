@testable import widgets

/// Answers the device-owner check with a scripted result and counts the prompts.
actor TestOwner: OwnerAuthenticating {
    private let error: (any Error)?
    private(set) var prompts = 0

    /// Configures one test's answer.
    /// - Parameter error: The error every check throws, if any.
    init(error: (any Error)? = nil) {
        self.error = error
    }

    /// Counts the prompt and returns or throws the scripted answer.
    /// - Parameter reason: The prompt's explanation.
    /// - Throws: The scripted failure.
    func confirmOwner(reason: String) async throws {
        prompts += 1
        if let error { throw error }
    }
}
