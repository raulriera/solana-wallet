/// Accepts a provider entry, such as an API key or an RPC URL, only after the person submits it.
@MainActor
protocol ProviderSubmitting<EntryError> {
    associatedtype EntryError: ProviderEntryError

    /// Why the provider rejected the entry, while it shows under the field.
    var rejection: EntryError? { get }
    /// Whether an accepted entry is still being checked, so the screen keeps its input locked until it ends.
    var isPending: Bool { get }

    /// Requests one check of an entry.
    /// - Parameter entry: The text as entered.
    func submit(_ entry: String)
}
