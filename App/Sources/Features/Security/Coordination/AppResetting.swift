/// Deletes everything sensitive this app stores, so every window starts over.
@MainActor
protocol AppResetting {
    /// Deletes every recovery phrase, then every wallet, then the provider API key, and returns every window to onboarding.
    ///
    /// Each step deletes whatever remains, so retrying after a failure finishes the reset.
    /// Themes and appearance settings stay.
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws
}
