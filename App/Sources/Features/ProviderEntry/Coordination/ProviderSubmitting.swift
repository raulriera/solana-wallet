/// Accepts a provider entry, such as an API key or a URL, that the person submits.
@MainActor
protocol ProviderSubmitting<EntryError> {
    /// The error for a rejected or failed entry.
    associatedtype EntryError: ProviderEntryError

    /// Why the provider rejected the entry, or `nil` when it didn't.
    var rejection: EntryError? { get }
    /// Whether an accepted entry is still being checked.
    var isPending: Bool { get }

    /// Requests one check of an entry.
    ///
    /// - Parameter entry: The text as entered.
    func submit(_ entry: String)
}
