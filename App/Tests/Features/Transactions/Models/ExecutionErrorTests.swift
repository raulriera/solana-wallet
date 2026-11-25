import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

struct ExecutionErrorTests {
    private static let payer = try! Address("7ojbqZyHTdFHMo5WAJyttWEHwtwfStdkAMh8fme8wNFs")
    private static let recipient = try! Address("6d8tEyrqPqVbEr6Jpuc7BEyYekeMUTyzHEwdmcAYEmtK")
    private static let tokenAccount = try! Address("A7Csd6PpFzYtvF17bdxASoLTPZ1xxyeLudQgpKVYPTw1")
    private static let transaction = Transaction.fixture(
        accounts: [
            payer, recipient, tokenAccount, try! Address("11111111111111111111111111111111"),
            try! Address("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
            try! Address("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"),
            try! Address("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"),
        ],
        instructions: [
            .init(programIndex: 6, accountIndices: [0, 1], data: Data()),
            .init(programIndex: 3, accountIndices: [0, 1], data: Data()),
            .init(programIndex: 4, accountIndices: [2, 1, 0], data: Data()),
            .init(programIndex: 5, accountIndices: [2, 1, 0], data: Data()),
        ]
    )

    @Test(arguments: [
        (#""InsufficientFundsForFee""#, ExecutionError.insufficientFunds(ExecutionErrorTests.payer)),
        (#""AccountNotFound""#, .insufficientFunds(ExecutionErrorTests.payer)),
        (#"{"InsufficientFundsForRent":{"account_index":1}}"#, .insufficientFundsForRent(ExecutionErrorTests.recipient)),
        (#"{"InstructionError":[1,{"Custom":1}]}"#, .insufficientFunds(ExecutionErrorTests.payer)),
        (#"{"InstructionError":[2,{"Custom":1}]}"#, .insufficientFunds(ExecutionErrorTests.tokenAccount)),
        (#"{"InstructionError":[3,{"Custom":1}]}"#, .insufficientFunds(ExecutionErrorTests.tokenAccount)),
        (#"{"InstructionError":[0,{"Custom":1}]}"#, .program(instruction: 0, code: 1)),
        (#"{"InstructionError":[1,{"Custom":0}]}"#, .program(instruction: 1, code: 0)),
        (#"{"InstructionError":[0,"InvalidArgument"]}"#, .program(instruction: 0, code: nil)),
        (#""BlockhashNotFound""#, .expired),
    ])
    func `A reported error names its cause`(json: String, expected: ExecutionError) throws {
        let error = try Self.error(json)

        #expect(ExecutionError(error, in: Self.transaction) == expected)
    }

    @Test(arguments: [
        #""AlreadyProcessed""#,
        #"{"InsufficientFundsForRent":{"account_index":7}}"#,
        #"{"InstructionError":[4,{"Custom":1}]}"#,
        #"{"InstructionError":["first",{"Custom":1}]}"#,
        #"{"InstructionError":[0,{"Custom":4294967296}]}"#,
        #"{"InstructionError":[0,{"Custom":"one"}]}"#,
        #"{"InstructionError":[0]}"#,
    ])
    func `An error without a known cause stays as Solana reports it`(json: String) throws {
        let error = try Self.error(json)

        #expect(ExecutionError(error, in: Self.transaction) == .other(error))
    }

    private static func error(_ json: String) throws -> TransactionError {
        try JSONDecoder().decode(TransactionError.self, from: Data(json.utf8))
    }
}
