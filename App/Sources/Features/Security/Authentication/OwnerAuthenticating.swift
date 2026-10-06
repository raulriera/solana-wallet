/// Confirms the device owner before a destructive action.
nonisolated protocol OwnerAuthenticating: Sendable {
    /// Asks the device owner to authenticate with biometrics or the device passcode.
    ///
    /// Returns without asking when the device has no passcode, because there's nothing to unlock.
    /// - Parameter reason: A localized explanation shown in the system prompt.
    /// - Throws: `CancellationError` if the user dismisses the prompt, or the authentication error.
    func confirmOwner(reason: String) async throws
}
