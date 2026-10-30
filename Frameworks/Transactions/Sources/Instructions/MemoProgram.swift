import Foundation

/// Instruction constructors for the Memo Program.
public enum MemoProgram {
    /// Creates a memo instruction.
    ///
    /// - Parameters:
    ///   - text: The memo text.
    ///   - signers: The accounts that must sign the memo.
    /// - Returns: The memo instruction.
    /// - Throws: An address validation error if the program identifier is invalid.
    public static func memo(_ text: String, signers: [Address] = []) throws -> Instruction {
        Instruction(program: try Address("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"),
                    accounts: signers.map { .init(address: $0, isSigner: true, isWritable: false) },
                    data: Data(text.utf8))
    }
}
