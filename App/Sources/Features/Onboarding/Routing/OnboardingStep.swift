/// One onboarding screen, pushed above welcome in the order the person reaches it.
nonisolated enum OnboardingStep: Hashable, Sendable {
    /// Backup of a newly prepared recovery phrase.
    case recovery
    /// Entry of an existing recovery phrase.
    case importWallet
    /// The choice of the RPC provider after the wallet is saved.
    case providers
    /// A screen that the provider choice pushes, such as a custom RPC's entry.
    case providersRoute(ProvidersRoute)

    /// The number of steps in every flow: the wallet's own step, then the provider choice.
    static let total = 2

    /// This step's position in its flow, counting from one; the provider choice's screens all count as its step.
    var number: Int {
        switch self {
        case .recovery, .importWallet: 1
        case .providers, .providersRoute: 2
        }
    }
}
