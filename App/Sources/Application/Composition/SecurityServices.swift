/// Shared services that show recovery and reset the app, supplied to every window's settings.
struct SecurityServices {
    /// Reads a wallet's recovery after authentication.
    let recovery: any RecoveryRevealing
    /// Confirms the device owner before a reset.
    let owner: any OwnerAuthenticating
    /// Deletes everything sensitive and returns every window to onboarding.
    let reset: any AppResetting
    /// Copies recovery words to this device only, for a limited time.
    let pasteboard: any RecoveryCopying
}
