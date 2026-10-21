/// A top-level section of a wallet window, shown as a tab.
///
/// Each window saves its section's raw value with its scene state. Add cases, but never rename or reuse a raw value.
nonisolated enum WalletSection: String {
    case portfolio
    #if DEBUG
    // The Contacts tab, a mock with sample data for now; its name isn't final, so release builds don't store it.
    case contacts
    #endif
    case settings
}
