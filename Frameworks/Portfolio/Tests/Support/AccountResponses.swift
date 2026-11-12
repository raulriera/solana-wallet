import Foundation
import Testing
@testable import Portfolio
@testable import RPC
@testable import Transactions

let testWallet = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
let otherWallet = "4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T"
let usdcMint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
let usdtMint = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
let pyusdMint = "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"
let nativeMint = "So11111111111111111111111111111111111111112"

struct Ledger: Sendable {
    var slot: UInt64 = 100
    var lamports: UInt64? = 100
    var tokens: [String: UInt64] = [:]
    var corrupt: Set<String> = []
    var otherOwners: [String: String] = [:]
    var prefunded: Set<String> = []
}

actor AccountResponses: HTTPTransport {
    typealias Responder = @Sendable ([String]) async throws -> Ledger
    typealias LogoResponder = @Sendable ([String]) async throws -> [String: String]

    private nonisolated let network: Network
    private(set) var requests: [[String]] = []
    private(set) var minimumSlots: [UInt64?] = []
    private(set) var logoRequests: [[String]] = []
    private let respond: Responder
    private let logos: LogoResponder

    nonisolated var client: SolanaRPC {
        SolanaRPC(network: network, transport: self)
    }

    nonisolated var heliusClient: HeliusRPC {
        HeliusRPC(apiKey: "fixture-key", network: network, transport: self)
    }

    init(network: Network = .mainnet, logos: @escaping LogoResponder = { _ in [:] }, respond: @escaping Responder) {
        self.network = network
        self.logos = logos
        self.respond = respond
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let body = try requestBody(request)
        let result: Any
        if body["method"] as? String == "getAssetBatch" {
            result = try await assets(for: try #require((body["params"] as? [String: Any])?["ids"] as? [String]))
        } else {
            try #require(body["method"] as? String == "getMultipleAccounts")
            let params = try #require(body["params"] as? [Any])
            minimumSlots.append((params.last as? [String: Any])?["minContextSlot"] as? UInt64)
            result = try await accounts(at: try requestedAddresses(request))
        }
        return try rpcReply(to: body, result: result, request: request)
    }

    private func accounts(at addresses: [String]) async throws -> Any {
        requests.append(addresses)
        let ledger = try await respond(addresses)
        let accounts = try addresses.enumerated().map { index, address in
            try index == 0 ? walletAccount(ledger) : tokenAccount(at: address, owner: addresses[0], in: ledger)
        }
        return ["context": ["slot": ledger.slot], "value": accounts] as [String: Any]
    }

    private func assets(for mints: [String]) async throws -> Any {
        logoRequests.append(mints)
        return assetBatch(for: mints, logos: try await logos(mints))
    }

    private func walletAccount(_ ledger: Ledger) -> Any {
        guard let lamports = ledger.lamports else { return NSNull() }
        return ["owner": "11111111111111111111111111111111", "lamports": lamports, "executable": false,
                "data": ["", "base64"]] as [String: Any]
    }

    private func tokenAccount(at address: String, owner: String, in ledger: Ledger) throws -> Any {
        let wallet = try Address(owner)
        for (mint, units) in ledger.tokens {
            let token = try Address(mint)
            for program in TokenProgram.allCases where try program.associatedAccount(owner: wallet, mint: token).value == address {
                let holder = try ledger.otherOwners[mint].map(Address.init) ?? wallet
                let data = ledger.corrupt.contains(mint) ? Data([1, 2, 3])
                    : tokenAccountData(mint: token, owner: holder, units: units, program: program)
                return ["owner": program.rawValue, "lamports": 2_039_280, "executable": false,
                        "data": [data.base64EncodedString(), "base64"]] as [String: Any]
            }
        }
        for mint in ledger.prefunded {
            let token = try Address(mint)
            for program in TokenProgram.allCases where try program.associatedAccount(owner: wallet, mint: token).value == address {
                return ["owner": "11111111111111111111111111111111", "lamports": 890_880, "executable": false,
                        "data": ["", "base64"]] as [String: Any]
            }
        }
        return NSNull()
    }
}

func tokenAccountData(mint: Address, owner: Address, units: UInt64, program: TokenProgram) -> Data {
    var bytes = mint.bytes + owner.bytes + withUnsafeBytes(of: units.littleEndian, Array.init)
    bytes += [UInt8](repeating: 0, count: 36)
    bytes += [1]
    bytes += [UInt8](repeating: 0, count: 20)
    bytes += [UInt8](repeating: 0, count: 36)
    if program == .token2022 { bytes += [2, 7, 0, 0, 0] }
    return Data(bytes)
}

func isolatedTokenLists() -> FileTokenListStore {
    FileTokenListStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
}
