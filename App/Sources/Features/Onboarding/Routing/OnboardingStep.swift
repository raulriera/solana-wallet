/// One onboarding screen, pushed above welcome in the order the person reaches it.
nonisolated enum OnboardingStep: Hashable, Sendable {
    /// Backup of a newly prepared recovery phrase.
    case recovery
    /// Entry of an existing recovery phrase.
    case importWallet
    /// Connection to the RPC provider after the wallet is saved.
    case providerSetup

    /// The number of steps in every flow: the wallet's own step, then provider setup.
    static let total = 2

    /// This step's position in its flow, counting from one.
    var number: Int {
        switch self {
        case .recovery, .importWallet: 1
        case .providerSetup: 2
        }
    }
}
