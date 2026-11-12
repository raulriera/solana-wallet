import Foundation

/// Instruction constructors for the Memo Program.
public enum MemoProgram: Program {
    /// The Memo Program's address.
    public static let id = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"

    /// Creates a memo instruction.
    ///
    /// - Parameters:
    ///   - text: The memo text.
    ///   - signers: The accounts that must sign the memo.
    /// - Returns: The memo instruction.
    /// - Throws: An address validation error if the program identifier is invalid.
    public static func memo(_ text: String, signers: [Address] = []) throws -> Instruction {
        Instruction(program: try address,
                    accounts: signers.map { .readonly($0, isSigner: true) },
                    data: Data(text.utf8))
    }
}
