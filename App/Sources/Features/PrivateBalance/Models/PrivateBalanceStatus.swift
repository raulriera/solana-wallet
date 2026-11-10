import Privacy

/// The state of an account's private balance on a network.
nonisolated enum PrivateBalanceStatus: Equatable, Sendable {
    /// The available and pending amounts of one asset, in its smallest unit.
    struct Balance: Equatable, Sendable {
        static let zero = Balance(available: 0, pending: 0)

        let available: UInt64
        let pending: UInt64
    }

    /// The balance of each asset, where an asset without one has a zero balance.
    struct Balances: Equatable, Sendable {
        private let balances: [PrivateAsset: Balance]

        /// The assets with an available or pending amount.
        var assets: Set<PrivateAsset> { Set(balances.keys) }

        /// Whether any asset has a pending amount.
        var hasPending: Bool { balances.values.contains { $0.pending > 0 } }

        /// Creates the balances of assets, leaving out zero balances.
        ///
        /// - Parameter balances: The balance of each asset.
        init(_ balances: [PrivateAsset: Balance]) {
            self.balances = balances.filter { $0.value != .zero }
        }

        subscript(asset: PrivateAsset) -> Balance { balances[asset] ?? .zero }
    }

    /// This device has no keys for the account, where `isRegistered` is whether the registry holds the account.
    case off(isRegistered: Bool)
    /// The selected provider doesn't serve the network.
    case unavailable
    /// The account has keys, but hasn't registered them on the network.
    case unregistered
    /// The account's balance of each asset.
    case balance(Balances)

    /// Returns the balance that an account's synced notes hold.
    ///
    /// - Parameter state: The account's notes.
    /// - Returns: The available and pending balance of each asset.
    static func balance(of state: NoteSyncState) -> PrivateBalanceStatus {
        .balance(Balances(Dictionary(uniqueKeysWithValues: PrivateAsset.allCases.map { ($0, $0.balance(in: state)) })))
    }

    /// Returns the balance of an asset.
    ///
    /// - Parameter asset: The asset.
    /// - Returns: The asset's balance, or `nil` without a balance.
    func balance(of asset: PrivateAsset) -> Balance? {
        guard case .balance(let balances) = self else { return nil }
        return balances[asset]
    }
}
