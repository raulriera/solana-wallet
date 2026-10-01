import Testing
import Transactions

/// Verifies native transfer input restrictions through the public API.
struct SystemProgramTests {
    /// Verifies zero lamports cannot become a wallet transfer instruction.
    @Test("SOL transfers reject zero lamports")
    func transfersRejectZeroLamports() throws {
        let sender = try Address(MessageFixture.sender)
        let recipient = try Address(MessageFixture.recipient)

        #expect(throws: ValidationError.invalidAmount) {
            try SystemProgram.transfer(from: sender, to: recipient, lamports: 0)
        }
    }

    /// Verifies the invoked program cannot also become a writable transfer account.
    ///
    /// - Parameter programIsSender: Whether to supply the System Program as the source.
    @Test("SOL transfers reject the System Program as a transfer account", arguments: [true, false])
    func transfersRejectProgramAccounts(programIsSender: Bool) throws {
        let account = try Address(MessageFixture.sender)
        let program = try Address(MessageFixture.zeroBlockhash)

        #expect(throws: ValidationError.programAddressAsTransferAccount) {
            try SystemProgram.transfer(from: programIsSender ? program : account, to: programIsSender ? account : program, lamports: 1)
        }
    }
}
