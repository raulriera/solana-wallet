import Observation

/// Keeps provider key entry transient and tracks whether there is a key to submit.
@MainActor
@Observable
final class ProviderKeyInput {
    var key = "" {
        didSet { hasKey = key.contains { !$0.isWhitespace } }
    }
    private(set) var hasKey = false
}
