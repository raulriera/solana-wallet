/// The services that show recovery and reset the app.
struct SecurityServices {
    let recovery: any RecoveryRevealing
    let owner: any OwnerAuthenticating
    let reset: any AppResetting
    let pasteboard: any RecoveryCopying
}
