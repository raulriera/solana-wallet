/// Checks and saves what a person entered for an RPC provider, such as an API key or an RPC URL.
nonisolated protocol ProviderConnecting<EntryError>: Sendable {
    /// The failure that explains a refused or failed entry.
    associatedtype EntryError: ProviderEntryError

    /// Checks an entry with the provider, saves it on this device, and tells every window.
    /// - Parameter entry: The text as entered; surrounding whitespace is ignored.
    /// - Throws: `EntryError` or `CancellationError`, never containing the entry.
    func connect(_ entry: String) async throws
}

nonisolated extension ProviderConnecting {
    /// The account that provider checks read: native SOL's mint, which exists on every network and holds no one's data.
    static var checkedAccount: String { "So11111111111111111111111111111111111111112" }
}
