import Foundation

/// An error from checking what a person entered for a provider, such as an API key, an RPC URL, or a price server URL.
nonisolated protocol ProviderEntryError: LocalizedError, Equatable, Sendable {
    /// The error for any unexpected failure.
    static var unavailable: Self { get }

    /// Whether the provider rejected the entry itself.
    var rejectsEntry: Bool { get }

    /// The explanation of the error.
    var message: LocalizedStringResource { get }
}

nonisolated extension ProviderEntryError {
    var recoverySuggestion: String? { String(localized: message) }
}
