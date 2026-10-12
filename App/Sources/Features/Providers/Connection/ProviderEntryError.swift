import Foundation

/// A failure from checking what a person entered for an RPC provider, such as an API key or an RPC URL.
///
/// It never contains the entry or underlying error text.
nonisolated protocol ProviderEntryError: LocalizedError, Equatable, Sendable {
    /// The failure for anything unexpected, explained in an alert.
    static var unavailable: Self { get }

    /// Whether the provider refused the entry itself, so the screen explains it under the field, not in an alert.
    var rejectsEntry: Bool { get }

    /// Explains the failure without the entry or underlying error text.
    var message: LocalizedStringResource { get }
}
