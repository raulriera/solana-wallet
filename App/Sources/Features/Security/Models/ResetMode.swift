/// Why the user resets the app, which decides the explanation and whether the device owner confirms first.
enum ResetMode: Hashable {
    /// The user chose Reset App, so the device owner confirms first.
    case standard
    /// This device no longer has the wallet's recovery, so resetting is the only fix and nothing needs unlocking.
    case recoveryUnavailable
}
