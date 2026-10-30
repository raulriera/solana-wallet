/// A screen that Security & Privacy pushes.
enum SecurityRoute: Hashable {
    case recoveryBackup
    /// The explanation of what a reset deletes.
    case resetApp(ResetMode)
    case resetConfirmation
}
