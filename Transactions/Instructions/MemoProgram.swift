import Foundation

/// Instruction constructors for Solana's Memo Program.
public enum MemoProgram {
    /// Creates a UTF-8 memo with optional accounts whose signatures the program verifies.
    ///
    /// - Parameters:
    ///   - text: The memo to record on-chain.
    ///   - signers: Accounts required to sign this memo. The default is empty.
    /// - Returns: A composable memo instruction; transaction limits are checked during compilation.
    /// - Throws: An address validation error if the program identifier is invalid.
    public static func memo(_ text: String, signers: [Address] = []) throws -> Instruction {
        Instruction(program: try Address("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"),
                    accounts: signers.map { .init(address: $0, isSigner: true, isWritable: false) },
                    data: Data(text.utf8))
    }
}
