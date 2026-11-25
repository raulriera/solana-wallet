import RPC
import Transactions

/// Why a transaction can't run, or why a sent transaction failed.
nonisolated enum ExecutionError: Error, Codable, Equatable, Sendable {
    /// The account doesn't hold the SOL or tokens that the transaction takes from it, its fee included.
    case insufficientFunds(Address)
    /// The transaction would leave the account with less than its rent-exempt minimum.
    case insufficientFundsForRent(Address)
    /// An instruction failed, with the program's error code if the program returned its own error.
    case program(instruction: Int, code: UInt32?)
    /// The transaction's blockhash is no longer valid.
    case expired
    /// A failure that no other case describes, as Solana reports it.
    case other(TransactionError)
}

nonisolated extension ExecutionError {
    /// The programs whose error code 1 means that the instruction's first account lacks the lamports or tokens it
    /// sends.
    private static let fundsPrograms = Set([SystemProgram.id] + TokenProgram.allCases.map(\.rawValue))

    /// Creates an execution error from the error that Solana reports for a transaction.
    ///
    /// A funds program's error names the account only when the program runs as one of the transaction's own
    /// instructions; when another program invokes it, the error stays a program error.
    ///
    /// - Parameters:
    ///   - error: The error of a simulation or of a signature status.
    ///   - transaction: The transaction that the error is about.
    init(_ error: TransactionError, in transaction: Transaction) {
        self = Self.cause(of: error, in: transaction) ?? .other(error)
    }

    /// Returns the case that describes an error, or `nil` if none does.
    ///
    /// - Parameters:
    ///   - error: The error that Solana reports.
    ///   - transaction: The transaction that the error is about.
    /// - Returns: The error's case, or `nil` for an error without one or with details that don't match its variant.
    private static func cause(of error: TransactionError, in transaction: Transaction) -> ExecutionError? {
        let accounts = transaction.accounts
        switch (error.name, error.details) {
        case ("InsufficientFundsForFee", nil), ("AccountNotFound", nil):
            return accounts.first.map { .insufficientFunds($0.address) }
        case ("InsufficientFundsForRent", .object(let fields)):
            guard let index: Int = fields["account_index"]?.integer(), accounts.indices.contains(index) else {
                return nil
            }
            return .insufficientFundsForRent(accounts[index].address)
        case ("InstructionError", .array(let values)) where values.count == 2:
            guard let index: Int = values[0].integer(), transaction.instructions.indices.contains(index) else {
                return nil
            }
            guard case .object(let fields) = values[1], let custom = fields["Custom"] else {
                return .program(instruction: index, code: nil)
            }
            guard let code: UInt32 = custom.integer() else { return nil }
            let instruction = transaction.instructions[index]
            guard code == 1, fundsPrograms.contains(accounts[instruction.programIndex].address.value),
                  let source = instruction.accountIndices.first else {
                return .program(instruction: index, code: code)
            }
            return .insufficientFunds(accounts[source].address)
        case ("BlockhashNotFound", nil):
            return .expired
        default:
            return nil
        }
    }
}

private nonisolated extension TransactionError.Detail {
    /// Returns the detail's integer as another integer type.
    ///
    /// - Returns: The integer, or `nil` if the detail isn't an integer or the type can't hold it.
    func integer<Integer: BinaryInteger>() -> Integer? {
        guard case .integer(let value) = self else { return nil }
        return Integer(exactly: value)
    }
}
