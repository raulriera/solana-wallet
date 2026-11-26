import RPC

extension TransactionError {
    nonisolated static func instructionError(_ instruction: UInt64, custom code: UInt64) -> TransactionError {
        TransactionError(name: "InstructionError",
                         details: .array([.integer(instruction), .object(["Custom": .integer(code)])]))
    }
}
