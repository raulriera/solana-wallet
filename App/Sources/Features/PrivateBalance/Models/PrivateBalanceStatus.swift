/// What an account's private balance shows on a network after a refresh.
nonisolated enum PrivateBalanceStatus: Equatable, Sendable {
    /// Private balances aren't turned on for the account: this device has no keys for it.
    case off
    /// The network has no private balances, or the selected provider doesn't read them.
    case unavailable
    /// The account has keys, but hasn't registered them on the network.
    case unregistered
    /// The account's unspent private SOL, in lamports.
    case lamports(UInt64)
}
