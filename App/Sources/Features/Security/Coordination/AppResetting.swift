/// Deletes everything sensitive this app stores, so every window starts over.
@MainActor
protocol AppResetting {
    /// Deletes every recovery phrase, then the private-balance keys and notes, then every saved and cached file, such
    /// as wallets, themes, and token lists, restarts appearance, erases each shared store, then deletes the provider
    /// API key, then the provider choice and custom RPCs, and returns every window to onboarding.
    ///
    /// Each step deletes whatever remains, so retrying after a failure finishes the reset.
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws
}
