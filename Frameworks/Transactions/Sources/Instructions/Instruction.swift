public import Foundation

/// An ordered program invocation before transaction account indices are assigned.
///
/// Account permissions are merged across instructions during compilation. Data
/// remains opaque; constructing an instruction doesn't establish its safety.
public struct Instruction: Sendable, Equatable {
    /// The program to invoke.
    public let program: Address
    /// The accounts in the order required by the program, including repeated entries.
    public let accounts: [Transaction.Account]
    /// The program-specific instruction data.
    public let data: Data

    /// Creates an invocation without compiling, signing, or submitting it.
    ///
    /// - Parameters:
    ///   - program: The invoked program's address.
    ///   - accounts: The ordered accounts and their required permissions.
    ///   - data: The payload interpreted by the program.
    public init(program: Address, accounts: [Transaction.Account] = [], data: Data = Data()) {
        self.program = program
        self.accounts = accounts
        self.data = data
    }
}
