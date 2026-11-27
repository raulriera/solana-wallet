import RPC
import Transactions

/// Why a transaction can't run, or why a sent transaction failed.
nonisolated enum ExecutionError: Error, Equatable, Sendable {
    /// The account doesn't hold the SOL or tokens that the transaction takes from it, its fee included.
    case insufficientFunds(Address)
    /// The transaction would leave the account with less than its rent-exempt minimum.
    case insufficientFundsForRent(Address)
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
    /// instructions; when another program invokes it, the error stays as Solana reports it.
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
            return .insufficientFunds(transaction.feePayer)
        case ("InsufficientFundsForRent", .object(let fields)):
            guard let index = fields["account_index"]?.integer, accounts.indices.contains(index) else {
                return nil
            }
            return .insufficientFundsForRent(accounts[index].address)
        case ("InstructionError", .array(let values)) where values.count == 2:
            guard let index = values[0].integer, transaction.instructions.indices.contains(index),
                  case .object(let fields) = values[1], fields["Custom"] == .integer(1) else { return nil }
            let instruction = transaction.instructions[index]
            guard fundsPrograms.contains(accounts[instruction.programIndex].address.value),
                  let source = instruction.accountIndices.first else { return nil }
            return .insufficientFunds(accounts[source].address)
        default:
            return nil
        }
    }
}

private nonisolated extension TransactionError.Detail {
    /// The detail's integer, or `nil` if the detail isn't an integer or `Int` can't hold it.
    var integer: Int? {
        guard case .integer(let value) = self else { return nil }
        return Int(exactly: value)
    }
}
