import Testing
import Transactions

struct InstructionVectors: Decodable, Sendable {
    let program: String

    let deposits: [Deposit]

    let transacts: [Transact]

    struct Account: Decodable, Sendable {
        let address: String
        let isSigner: Bool
        let isWritable: Bool

        func account() throws -> Transaction.Account {
            Transaction.Account(address: try Address(address), isSigner: isSigner, isWritable: isWritable)
        }
    }

    struct Deposit: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let lamports: String
        let depositor: String
        let toSender: Bool
        let treeID: UInt16
        let data: String
        let accounts: [Account]

        var testDescription: String { name }
    }

    struct Transact: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let inputs: [Input]
        let transferLamports: UInt64?
        let withdrawalLamports: UInt64?
        let outputTreeID: UInt16
        let paddingInputs: Int
        let paddingOutputs: Int
        let treeContexts: [[UInt16]]
        let externalDataHash: String
        let privateTransactionHash: String
        let data: String
        let accounts: [Account]

        var testDescription: String { name }
    }

    struct Input: Decodable, Sendable {
        let lamports: UInt64
        let treeID: UInt16
        let blindingByte: UInt8
    }

    static func load() throws -> Self {
        try fixture(named: "InstructionVectors")
    }
}
