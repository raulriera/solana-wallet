import Foundation

/// A client for Helius Sender's mainnet transaction-submission service.
public struct Sender: RPC {
    /// A Sender routing tier.
    public enum Tier: Sendable {
        /// Delivery through stake-weighted routing with a lower tip.
        case standard
        /// Delivery through all Sender routes with a higher tip.
        case premium
    }

    public let network: Network = .mainnet
    public let tier: Tier
    public let submissionRequirements: SubmissionRequirements?

    private let client: HTTPClient

    /// Creates a client for a routing tier.
    ///
    /// - Parameter tier: The routing tier.
    public init(tier: Tier) {
        self.tier = tier
        submissionRequirements = SubmissionRequirements(
            tipRecipient: Self.tipAccounts[Int.random(in: Self.tipAccounts.indices)],
            tipLamports: tier == .premium ? 1_000_000 : 5_000,
            minimumPriorityFeeLamports: tier == .premium ? 5_000 : 1
        )
        // swift-format-ignore: NeverForceUnwrap
        var endpoint = URL(string: "https://sender.helius-rpc.com/fast")!
        if tier == .standard {
            endpoint.append(queryItems: [URLQueryItem(name: "swqos_only", value: "true")])
        }
        client = HTTPClient(endpoint: endpoint, transport: URLSessionTransport(),
                            redactor: SecretRedactor(secrets: []))
    }

    public func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        try await client.send(request)
    }

    static let tipAccounts = [
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
