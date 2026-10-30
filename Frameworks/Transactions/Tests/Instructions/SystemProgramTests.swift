import Testing
import Transactions

struct SystemProgramTests {
    @Test
    func `SOL transfers reject zero lamports`() throws {
        let sender = try Address(MessageFixture.sender)
        let recipient = try Address(MessageFixture.recipient)

        #expect(throws: ValidationError.invalidAmount) {
            try SystemProgram.transfer(from: sender, to: recipient, lamports: 0)
        }
    }

    @Test(arguments: [true, false])
    func `SOL transfers reject the System Program as a transfer account`(programIsSender: Bool) throws {
        let account = try Address(MessageFixture.sender)
        let program = try Address(MessageFixture.zeroBlockhash)

        #expect(throws: ValidationError.programAddressAsTransferAccount) {
            try SystemProgram.transfer(from: programIsSender ? program : account, to: programIsSender ? account : program, lamports: 1)
        }
    }
}
