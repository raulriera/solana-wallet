import Observation

/// A provider entry, such as an API key or an RPC URL, and whether it has text to submit.
@MainActor
@Observable
final class ProviderEntryModel {
    var text = "" {
        didSet { hasText = text.contains { !$0.isWhitespace } }
    }
    private(set) var hasText = false
}
