/// A service that deletes everything the app saves.
@MainActor
protocol AppResetting {
    /// Deletes every secret, store, and file that the app saves.
    ///
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws
}
