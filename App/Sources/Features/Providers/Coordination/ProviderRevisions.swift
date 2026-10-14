/// The app-wide counts of provider changes that every window responds to.
struct ProviderRevisions {
    /// Advances after every saved provider setting: the choice, a custom RPC, or Helius's key.
    ///
    /// Each window's provider list reads the settings again.
    let settings = Revision()
    /// Advances only when portfolios read through another provider or with a new Helius key.
    ///
    /// Each window observes its portfolio again; an edit that keeps the connection, such as deleting an unused
    /// custom RPC, leaves observation running.
    let connection = Revision()
}
