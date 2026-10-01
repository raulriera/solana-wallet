import Foundation

/// A client for Helius Sender's optional mainnet transaction-submission service.
///
/// Use this client as the selected submission route. It serves submission methods;
/// preparation and confirmation continue through an ordinary RPC client.
public struct Sender: RPC {
    /// The Sender routing tier selected by the app's settings.
    public enum Tier: Sendable, CaseIterable, Equatable {
        /// Lower-cost delivery through Helius's stake-weighted routing.
        case standard
        /// Broader delivery through all Helius Sender routes, with a higher tip.
        case premium
    }

    /// Sender's documented endpoints serve mainnet.
    public let network: Network = .mainnet
    /// The selected routing tier.
    public let tier: Tier
    /// The tip and priority-fee requirements to include before signing.
    public let submissionRequirements: SubmissionRequirements?

    private let client: HTTPClient

    /// Creates a Sender client using its public HTTPS endpoint and the tier's minimum tip.
    ///
    /// A tip recipient is selected once per client so preparation and submission
    /// share stable requirements. Standard Sender access doesn't require an API key.
    ///
    /// - Parameter tier: The routing tier chosen by the user.
    public init(tier: Tier) {
        self.tier = tier
        submissionRequirements = SubmissionRequirements(
            tipRecipient: Self.tipAccounts.randomElement()!,
            tipLamports: tier == .premium ? 1_000_000 : 5_000,
            minimumPriorityFeeLamports: tier == .premium ? 5_000 : 1
        )
        var endpoint = URL(string: "https://sender.helius-rpc.com/fast")!
        if tier == .standard {
            endpoint.append(queryItems: [URLQueryItem(name: "swqos_only", value: "true")])
        }
        client = HTTPClient(endpoint: endpoint, transport: URLSessionTransport(),
                            redactor: SecretRedactor(secrets: []))
    }

    /// Sends one request without changing its transaction, preflight policy, or retry limit.
    ///
    /// - Parameter request: A submission request accepted by Sender.
    /// - Returns: The validated response associated with the request.
    /// - Throws: An `RPCError` or `CancellationError`.
    public func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await client.send(request)
    }

    /// Helius's published mainnet tip accounts, distributed to reduce shared write locks.
    private static let tipAccounts = [
        "4ACfpUFoaSD9bfPdeu6DBt89gB6ENTeHBXCAi87NhDEE",
        "D2L6yPZ2FmmmTKPgzaMKdhu6EWZcTpLy1Vhx8uvZe7NZ",
        "9bnz4RShgq1hAnLnZbP8kbgBg1kEmcJBYQq3gQbmnSta",
        "5VY91ws6B2hMmBFRsXkoAAdsPHBJwRfBht4DXox3xkwn",
        "2nyhqdwKcJZR2vcqCyrYsaPVdAnFoJjiksCXJ7hfEYgD",
        "2q5pghRs6arqVjRvT5gfgWfWcHWmw1ZuCzphgd5KfWGJ",
        "wyvPkWjVZz1M8fHQnMMCDTQDbkManefNNhweYk5WkcF",
        "3KCKozbAaF75qEU33jtzozcJ29yJuaLJTy2jFdzUY8bT",
        "4vieeGHPYPG2MmyPRcYjdiDmmhN3ww7hsFNap8pVN3Ey",
        "4TQLFNWK8AovT1gFvda5jfw2oJeRMKEmw7aH6MGBJ3or",
    ]
}
