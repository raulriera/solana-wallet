import Foundation
import Testing
@testable import RPC

/// Mint-lookup HTTP fixtures decoded by the real RPC clients.
actor LookupResponses: HTTPTransport {
    /// Supplies the CDN logo URL of each requested mint that has one, for one DAS logo lookup.
    typealias LogoResponder = @Sendable ([String]) async throws -> [String: String]

    private let accounts: [String: Account]
    private let logos: LogoResponder
    private(set) var requests: [[String]] = []
    private(set) var logoRequests: [[String]] = []

    /// The real public-endpoint client receiving the fixture's HTTP responses.
    nonisolated var client: Solana {
        Solana(network: .mainnet, transport: self)
    }

    /// The real Helius client, which also looks up logos through DAS.
    nonisolated var heliusClient: HeliusRPC {
        HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: self)
    }

    /// Creates lookups that find only the given accounts.
    /// - Parameters:
    ///   - accounts: The accounts that exist, keyed by address.
    ///   - logos: The logo supplier for DAS lookups, which may fail a request; the default has no logos.
    init(accounts: [String: Account], logos: @escaping LogoResponder = { _ in [:] }) {
        self.accounts = accounts
        self.logos = logos
    }

    /// Records the requested addresses or mints and returns their accounts or assets in a JSON-RPC envelope.
    /// - Parameter request: The HTTP request created by the RPC client.
    /// - Returns: The fixture's response data and HTTP metadata.
    /// - Throws: A fixture, transport, or cancellation error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let body = try rpcBody(request)
        let result: Any
        if body["method"] as? String == "getAssetBatch" {
            let mints = try #require((body["params"] as? [String: Any])?["ids"] as? [String])
            logoRequests.append(mints)
            result = assetBatch(for: mints, logos: try await logos(mints))
        } else {
            try #require(body["method"] as? String == "getMultipleAccounts")
            let addresses = try #require((body["params"] as? [Any])?.first as? [String])
            requests.append(addresses)
            let values = addresses.map { address -> Any in
                guard let account = accounts[address] else { return NSNull() }
                return ["owner": account.owner, "lamports": account.lamports, "executable": account.executable,
                        "data": [account.data.base64EncodedString(), "base64"]] as [String: Any]
            }
            result = ["context": ["slot": 100], "value": values] as [String: Any]
        }
        return try rpcReply(to: body, result: result, request: request)
    }
}
