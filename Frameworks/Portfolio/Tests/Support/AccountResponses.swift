import Foundation
@testable import Portfolio
import Testing
@testable import RPC
@testable import Transactions

/// A public wallet whose balances in these tests come only from local fixtures.
let testWallet = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
/// A second public wallet for checks that keep wallets apart.
let otherWallet = "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"
/// The USD Coin mint, a default token on mainnet.
let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
/// The USDT mint, a default token on mainnet.
let usdtMint = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
/// The mint that native SOL shares with Wrapped SOL for prices.
let nativeMint = "So11111111111111111111111111111111111111112"

/// The ledger state a balance-read fixture reports.
struct Ledger: Sendable {
    /// The wallet's SOL balance in lamports, or `nil` when the wallet has no account.
    var lamports: UInt64? = 100
    /// The balances of the token accounts that exist, keyed by mint address.
    var tokens: [String: UInt64] = [:]
    /// Mints whose token accounts hold bytes that aren't a token account.
    var corrupt: Set<String> = []
}

/// Balance-read HTTP fixtures decoded by the real RPC client during portfolio refreshes.
actor AccountResponses: HTTPTransport {
    /// Supplies the ledger state for one balance read of the requested addresses.
    typealias Responder = @Sendable ([String]) async throws -> Ledger

    private nonisolated let network: Network
    private(set) var requests: [[String]] = []
    private let respond: Responder

    /// The real public-endpoint client receiving the fixture's HTTP responses.
    nonisolated var client: Solana {
        Solana(network: network, transport: self)
    }

    /// Creates isolated balance reads for cache, refresh, and cancellation checks.
    /// - Parameters:
    ///   - network: The network associated with cached snapshots.
    ///   - respond: The ledger supplier, which may suspend or fail a request.
    init(network: Network = .mainnet, respond: @escaping Responder) {
        self.network = network
        self.respond = respond
    }

    /// Records the requested addresses and returns their accounts in a JSON-RPC envelope.
    /// - Parameter request: The HTTP request created by the RPC client.
    /// - Returns: The fixture's response data and HTTP metadata.
    /// - Throws: A fixture, transport, or cancellation error.
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try #require(body["method"] as? String == "getMultipleAccounts")
        let params = try #require(body["params"] as? [Any])
        let addresses = try #require(params.first as? [String])
        requests.append(addresses)
        let ledger = try await respond(addresses)
        let accounts = try addresses.enumerated().map { index, address in
            try index == 0 ? walletAccount(ledger) : tokenAccount(at: address, owner: addresses[0], in: ledger)
        }
        let result: [String: Any] = ["context": ["slot": 100], "value": accounts]
        let envelope: [String: Any] = ["jsonrpc": "2.0", "id": try #require(body["id"]), "result": result]
        let url = try #require(request.url)
        return (try JSONSerialization.data(withJSONObject: envelope),
                try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
    }

    /// Encodes the wallet's system account, or a missing account.
    /// - Parameter ledger: The ledger state to report.
    /// - Returns: The account's JSON value.
    private func walletAccount(_ ledger: Ledger) -> Any {
        guard let lamports = ledger.lamports else { return NSNull() }
        return ["owner": "11111111111111111111111111111111", "lamports": lamports, "executable": false,
                "data": ["", "base64"]] as [String: Any]
    }

    /// Encodes the token account at an address when it's an existing associated account in the ledger.
    /// - Parameters:
    ///   - address: The requested associated token account.
    ///   - owner: The wallet whose token accounts the ledger describes.
    ///   - ledger: The ledger state to report.
    /// - Returns: The account's JSON value, or a missing account.
    /// - Throws: A validation error for a malformed fixture address.
    private func tokenAccount(at address: String, owner: String, in ledger: Ledger) throws -> Any {
        let wallet = try Address(owner)
        for (mint, units) in ledger.tokens {
            let token = try Address(mint)
            for program in TokenProgram.allCases where try program.associatedAccount(owner: wallet, mint: token).value == address {
                let data = ledger.corrupt.contains(mint) ? Data([1, 2, 3])
                    : tokenAccountData(mint: token, owner: wallet, units: units, program: program)
                return ["owner": program.rawValue, "lamports": 2_039_280, "executable": false,
                        "data": [data.base64EncodedString(), "base64"]] as [String: Any]
            }
        }
        return NSNull()
    }
}

/// Encodes an initialized token account as the token programs store it.
///
/// Token-2022 accounts carry the immutable-owner extension that associated accounts receive.
/// - Parameters:
///   - mint: The mint whose tokens the account holds.
///   - owner: The wallet that owns the account.
///   - units: The balance in the token's smallest units.
///   - program: The token program that owns the account.
/// - Returns: The account's raw bytes.
func tokenAccountData(mint: Address, owner: Address, units: UInt64, program: TokenProgram) -> Data {
    var bytes = mint.bytes + owner.bytes + withUnsafeBytes(of: units.littleEndian, Array.init)
    bytes += [UInt8](repeating: 0, count: 36) // No delegate.
    bytes += [1] // Initialized.
    bytes += [UInt8](repeating: 0, count: 20) // Not native, and nothing delegated.
    bytes += [UInt8](repeating: 0, count: 36) // No close authority.
    if program == .token2022 { bytes += [2, 7, 0, 0, 0] } // Account type, then an empty immutable-owner entry.
    return Data(bytes)
}

/// Creates a token-list store in a new temporary directory, which stays empty unless a test adds a token.
/// - Returns: A store that keeps a test's token lists apart from every other test.
func isolatedTokenLists() -> FileTokenListStore {
    FileTokenListStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
}
