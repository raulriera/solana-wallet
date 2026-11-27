import RPC

extension TransactionError {
    nonisolated static let insufficientFundsForFee = TransactionError(name: "InsufficientFundsForFee", details: nil)

    nonisolated static func insufficientFundsForRent(accountIndex: UInt64) -> TransactionError {
        TransactionError(name: "InsufficientFundsForRent", details: .object(["account_index": .integer(accountIndex)]))
    }

    nonisolated static func instructionError(_ instruction: UInt64, custom code: UInt64) -> TransactionError {
        TransactionError(name: "InstructionError",
                         details: .array([.integer(instruction), .object(["Custom": .integer(code)])]))
    }
}
