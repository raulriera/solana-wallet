import Foundation
import Testing
@testable import RPC

actor LookupResponses: HTTPTransport {
    typealias LogoResponder = @Sendable ([String]) async throws -> [String: String]

    private let accounts: [String: Account]
    private let logos: LogoResponder
    private(set) var requests: [[String]] = []
    private(set) var logoRequests: [[String]] = []

    nonisolated var client: SolanaRPC {
        SolanaRPC(network: .mainnet, transport: self)
    }

    nonisolated var heliusClient: HeliusRPC {
        HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: self)
    }

    init(accounts: [String: Account], logos: @escaping LogoResponder = { _ in [:] }) {
        self.accounts = accounts
        self.logos = logos
    }

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
