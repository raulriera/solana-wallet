/// One onboarding screen, pushed above welcome in the order the person reaches it.
nonisolated enum OnboardingStep: Hashable, Sendable {
    /// Backup of a newly prepared recovery phrase.
    case recovery
    /// Entry of an existing recovery phrase.
    case importWallet
    /// Connection to the RPC provider after the wallet is saved.
    case providerSetup
}
