/// A screen pushed inside Security & Privacy; routes never carry recovery material.
enum SecurityRoute: Hashable {
    /// The window's wallet backup, or the explanation that this device no longer has it.
    case recoveryBackup
    /// What a reset deletes, explained for the reason the user is resetting.
    case resetApp(ResetMode)
    /// The final reset confirmation.
    case resetConfirmation
}
