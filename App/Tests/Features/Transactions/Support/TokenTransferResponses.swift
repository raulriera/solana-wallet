import Encoding
import Foundation
import Testing
import Transactions

struct TokenTransferResponses {
    enum Destination: Sendable {
        case absent
        case funded(UInt64)
        case initialized
        case unsupportedOwner
        case nonemptySystem
        case executable
    }

    enum Recipient: Sendable {
        case wallet
        case programOwned
        case tokenAccount
        case otherMintTokenAccount
        case mint
        case program
    }

    let program: TokenProgram
    let sender: Address
    let recipient: Address
    let mint: Mint
    let source: Address
    let tokenAccount: Address

    init(program: TokenProgram) throws {
        self.program = program
        sender = try Address("4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T")
        recipient = try Address("9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM")
        mint = .fixture("A9ZcnduP9GUGGRLZk9zR2KPGuJnmLCz4Te5umhBKYhpX", program: program, decimals: 6)
        source = try Address("5HHw6ucspj8GLw691ziae7j9grFjcWoS3tmKStMLfGPD")
        tokenAccount = try program.associatedAccount(owner: recipient, mint: mint.address)
    }

    func http(destination: Destination, recipient: Recipient = .wallet,
              transferFee: (basisPoints: UInt16, maximum: UInt64)? = nil) throws -> HTTPResponses {
        let mintAccount = account(owner: program.rawValue, data: try transferFee.map(Self.feeMint) ?? Self.mintData)
        let hasFee = transferFee != nil
        let sourceData = try hasFee ? Self.feeAccount(Self.sourceData) : Self.sourceData
        let destinationData = try hasFee ? Self.feeAccount(Self.destinationData) : Self.destinationData
        let sourceAccount = account(owner: program.rawValue, data: sourceData)
        let destinationAccount: Any = switch destination {
        case .absent: NSNull()
        case .funded(let lamports): account(owner: Self.systemProgram, lamports: lamports)
        case .initialized: account(owner: program.rawValue, data: destinationData)
        case .unsupportedOwner: account(owner: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
        case .nonemptySystem: account(owner: Self.systemProgram, data: "AA==")
        case .executable: account(owner: Self.systemProgram, executable: true)
        }
        let recipientAccount: Any = switch recipient {
        case .wallet: account(owner: Self.systemProgram)
        case .programOwned: account(owner: "Stake11111111111111111111111111111111111111", data: "AA==")
        case .tokenAccount: account(owner: program.rawValue, data: Self.destinationData)
        case .otherMintTokenAccount: account(owner: program.rawValue, data: Self.otherMintAccount)
        case .mint: mintAccount
        case .program: account(owner: "BPFLoaderUpgradeab1e11111111111111111111111", executable: true)
        }
        return HTTPResponses([
            "getMultipleAccounts": [try HTTPResponses.json(["context": ["slot": 101], "value": [
                mintAccount, recipientAccount, sourceAccount, destinationAccount,
            ]])],
            "getEpochInfo": [#"{"epoch":1,"absoluteSlot":101,"blockHeight":91}"#],
            "getMinimumBalanceForRentExemption": ["2100000"],
        ])
    }

    private func account(owner: String, data: String = "", lamports: UInt64 = 2_100_000,
                         executable: Bool = false) -> [String: Any] {
        ["owner": owner, "lamports": lamports, "executable": executable, "rentEpoch": 0,
         "data": [data, "base64"]]
    }

    private static func feeMint(_ fee: (basisPoints: UInt16, maximum: UInt64)) throws -> String {
        var schedule = [UInt8](repeating: 0, count: 8)
        schedule.append(littleEndian: fee.maximum)
        schedule.append(littleEndian: fee.basisPoints)
        let configuration = [UInt8](repeating: 0, count: 72) + schedule + schedule
        return try extended(mintData, accountType: 1, entry: 1, value: configuration)
    }

    private static func feeAccount(_ account: String) throws -> String {
        try extended(account, accountType: 2, entry: 2, value: [UInt8](repeating: 0, count: 8))
    }

    private static func extended(_ account: String, accountType: UInt8, entry: UInt8, value: [UInt8]) throws -> String {
        var bytes = Array(try #require(Data(base64Encoded: account)))
        bytes += [UInt8](repeating: 0, count: 165 - bytes.count)
        bytes += [accountType, entry, 0, UInt8(value.count), 0] + value
        return Data(bytes).base64EncodedString()
    }

    private static let systemProgram = "11111111111111111111111111111111"

    private static let mintData = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//////////8GAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
    private static let sourceData = "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpwyHPpa3RheiJOl/YgBPsTX4SLe1GNUyt/1DZVjledbYP//////////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private static let destinationData = "h+q1gBJapZ/LBb6AmqRfdi8pFXsG3s8fywG2OC5pXpx+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    private static let otherMintAccount = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQF+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
}
