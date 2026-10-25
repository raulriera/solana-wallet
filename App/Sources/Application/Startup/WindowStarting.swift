import Foundation

/// Chooses one window's first destination from saved public account metadata.
@MainActor
protocol WindowStarting {
    /// Resolves startup or retries a failed read, preserving any existing destination.
    /// - Parameter accountID: The account this window showed before the system ended the app, if any.
    func restore(preferring accountID: UUID?) async
}
