import Foundation
import Transactions

/// Public SDK account fixtures returned through the real RPC client's HTTP boundary.
struct TokenTransferResponses {
    /// The recipient's canonical address before resolving a transfer.
    enum Destination: Sendable {
        case absent
        case funded(UInt64)
        case initialized
        case unsupportedOwner
        case nonemptySystem
        case executable
    }

    /// The account at the address entered as the recipient.
    enum Recipient: Sendable {
        case wallet
        case absent
        case programOwned
        case tokenAccount
        case otherMintTokenAccount
        case mint
        case program
    }

    let program: TokenProgram
    let sender: Address
    let recipient: Address
    let mint: Address
    let source: Address
    /// The recipient's associated token account, as someone would copy it from an explorer.
    let tokenAccount: Address

    /// Selects the token program for the published account layouts.
    /// - Parameter program: The first-party token program reported by RPC.
    /// - Throws: An address validation error if a public fixture is malformed.
    init(program: TokenProgram) throws {
        self.program = program
        sender = try Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T")
        recipient = try Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        mint = try Address("A9ZcnduP9GUGGRLZk9zR2KPGuJnmLCz4Te5umhBKYhpX")
        source = try Address("5HHw6ucspj8GLw691ziae7j9grFjcWoS3tmKStMLfGPD")
        tokenAccount = try program.associatedAccount(owner: recipient, mint: mint)
    }

    /// Supplies ordered discovery, snapshot, epoch, and rent responses without network access.
    /// - Parameters:
    ///   - destination: The observed account at the recipient's associated address.
    ///   - recipient: The observed account at the recipient address itself.
    ///   - defaultFrozen: Whether the Token-2022 mint initializes newly created accounts as frozen.
    /// - Returns: The isolated transport used by the real Helius RPC client.
    /// - Throws: A fixture JSON encoding error.
    func http(destination: Destination, recipient: Recipient = .wallet, defaultFrozen: Bool = false) throws -> HTTPResponses {
        let mintAccount = account(owner: program.rawValue, data: defaultFrozen ? Self.frozenMint : Self.mintData)
        let sourceAccount = account(owner: program.rawValue, data: Self.sourceData)
        let destinationAccount: Any = switch destination {
        case .absent: NSNull()
        case .funded(let lamports): account(owner: Self.systemProgram, lamports: lamports)
        case .initialized: account(owner: program.rawValue, data: Self.destinationData)
        case .unsupportedOwner: account(owner: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        case .nonemptySystem: account(owner: Self.systemProgram, data: "AA==")
        case .executable: account(owner: Self.systemProgram, executable: true)
        }
        let recipientAccount: Any = switch recipient {
        case .wallet: account(owner: Self.systemProgram)
        case .absent: NSNull()
        case .programOwned: account(owner: "Stake11111111111111111111111111111111111111", data: "AA==")
        case .tokenAccount: account(owner: program.rawValue, data: Self.destinationData)
        case .otherMintTokenAccount: account(owner: program.rawValue, data: Self.otherMintAccount)
        case .mint: mintAccount
        case .program: account(owner: "BPFLoaderUpgradeab1e11111111111111111111111", executable: true)
        }
        return HTTPResponses([
            "getMultipleAccounts": [
                try HTTPResponses.json(["context": ["slot": 100], "value": [mintAccount]]),
                try HTTPResponses.json(["context": ["slot": 101], "value": [mintAccount, sourceAccount, destinationAccount, recipientAccount]]),
            ],
            "getEpochInfo": [#"{"epoch":1,"absoluteSlot":101}"#],
            "getMinimumBalanceForRentExemption": ["2100000"],
        ])
    }

    /// Encodes one account using the provider's base64 wire representation.
    /// - Parameters:
    ///   - owner: The program owning the account.
    ///   - data: Its base64-encoded data, empty for an unallocated system account.
    ///   - lamports: Its existing native balance.
    ///   - executable: Whether the account represents an executable program.
    /// - Returns: The JSON-compatible account observation.
    private func account(owner: String, data: String = "", lamports: UInt64 = 2_100_000,
                         executable: Bool = false) -> [String: Any] {
        ["owner": owner, "lamports": lamports, "executable": executable, "rentEpoch": 0,
         "data": [data, "base64"]]
    }

    private static let systemProgram = "11111111111111111111111111111111"

    // These small layouts also appear in TransactionsTests' SDK-generated TokenFixture.
    // Framework test types are not linked into this app-hosted test target.
    private static let mintData = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
    private static let sourceData = "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwyHPpa3RheiJOl/YgBPsTX4SLe1GNUyt/1DZVjledbYP//////////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private static let destinationData = "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    // The destination layout with every mint byte set to one.
    private static let otherMintAccount = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQF+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private static let frozenMint = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQYAAQAC"
}
