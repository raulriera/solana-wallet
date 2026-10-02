/// Restores one window from saved public account metadata without modifying storage.
@MainActor
protocol WindowStarting {
    /// Resolves startup or retries a failed read, preserving any existing destination.
    func restore() async
}
