/// A service that confirms the device owner.
nonisolated protocol OwnerAuthenticating: Sendable {
    /// Asks the device owner to authenticate with biometrics or the device passcode.
    ///
    /// - Parameter reason: The localized reason that the prompt shows.
    /// - Throws: `CancellationError` if the person dismisses the prompt, or an authentication error.
    func confirmOwner(reason: String) async throws
}
