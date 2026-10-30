/// The reason for a reset.
enum ResetMode: Hashable {
    /// The person chose to reset the app.
    case standard
    /// The wallet's recovery isn't on this device.
    case recoveryUnavailable
}
