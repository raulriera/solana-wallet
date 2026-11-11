import Testing
import Transactions

struct TokenProgramTests {
    @Test(arguments: TokenFixtures.transfers.filter(\.createsDestination))
    func `Associated account creation matches the SDK's idempotent instruction`(_ fixture: TokenFixture) throws {
        let mint = try fixture.mint()
        let instruction = try mint.program.createAssociatedAccount(owner: Address(TokenFixtures.recipient),
                                                                   mint: mint.address, payer: Address(TokenFixtures.sender))
        let reference = try TransactionDecoder().decode(base64: fixture.wire)
        let expected = try #require(reference.instructions.first)

        #expect(instruction.program == reference.accounts[expected.programIndex].address)
        #expect(instruction.accounts.map(\.address) == expected.accountIndices.map { reference.accounts[$0].address })
        #expect(instruction.accounts.map(\.isSigner) == [true, false, false, false, false, false])
        #expect(instruction.accounts.map(\.isWritable) == [true, true, false, false, false, false])
        #expect(instruction.data == expected.data)
    }
}
