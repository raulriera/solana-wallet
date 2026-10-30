/// Checks and saves what a person entered for an RPC provider, such as an API key or an RPC URL.
nonisolated protocol ProviderConnecting<EntryError>: Sendable {
    /// The error for a rejected or failed entry.
    associatedtype EntryError: ProviderEntryError

    /// Checks an entry with the provider and saves it.
    ///
    /// - Parameter entry: The text as entered, without surrounding whitespace.
    /// - Throws: `EntryError` or `CancellationError`.
    func connect(_ entry: String) async throws
}

nonisolated extension ProviderConnecting {
    /// The account that provider checks read.
    static var checkedAccount: String { "So11111111111111111111111111111111111111112" }
}
