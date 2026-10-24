/// A top-level section of a wallet window, shown as a tab.
///
/// Each window saves its section's raw value with its scene state. Add cases, but never rename or reuse a raw value.
nonisolated enum WalletSection: String {
    case portfolio
    case contacts
    case settings
}
