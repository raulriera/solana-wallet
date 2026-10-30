public import Foundation

/// A program invocation before transaction account indices are assigned.
public struct Instruction: Sendable, Equatable {
    public let program: Address
    public let accounts: [Transaction.Account]
    public let data: Data

    /// Creates an instruction.
    ///
    /// - Parameters:
    ///   - program: The program's address.
    ///   - accounts: The accounts in order, with their permissions.
    ///   - data: The program-specific data.
    public init(program: Address, accounts: [Transaction.Account] = [], data: Data = Data()) {
        self.program = program
        self.accounts = accounts
        self.data = data
    }
}
