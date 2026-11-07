/// An onboarding screen above welcome.
nonisolated enum OnboardingStep: Hashable, Sendable {
    /// The backup of a new recovery phrase.
    case recovery
    case importWallet
    case rpc
    /// A screen that the provider choice pushes.
    case rpcRoute(RPCRoute)

    /// The number of steps in every flow.
    static let total = 2

    /// The step's position in its flow, counting from one.
    var number: Int {
        switch self {
        case .recovery, .importWallet: 1
        case .rpc, .rpcRoute: 2
        }
    }
}
