import Observation

/// Keeps a provider entry, such as an API key or an RPC URL, transient and tracks whether there is text to submit.
@MainActor
@Observable
final class ProviderEntryModel {
    var text = "" {
        didSet { hasText = text.contains { !$0.isWhitespace } }
    }
    private(set) var hasText = false
}
