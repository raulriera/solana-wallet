import Testing
import Transactions
@testable import Privacy

struct PrivateSpendTests {
    @Test
    func `Withdrawals pay SOL to the owner and a token to the owner's token account`() throws {
        let owner = try Address(TransferVectors.recipientSigningAddress)
        let destination = PrivateSpend.Destination.withdrawal(owner)
        let tokenAccount = try TokenProgram.token.associatedAccount(owner: owner, mint: PrivateToken.usdc.mint)

        #expect(try destination.parts(moving: 1, of: .nativeSOL).withdrawal
            == ExternalData.Withdrawal(recipient: owner, amount: 1, asset: .nativeSOL))
        #expect(try destination.parts(moving: 1, of: .token(.usdc)).withdrawal
            == ExternalData.Withdrawal(recipient: tokenAccount, amount: 1, asset: .token(.usdc)))
    }

    @Test(arguments: [PrivateAsset.nativeSOL, .token(.usdc)])
    func `Transfers carry no withdrawal`(asset: PrivateAsset) throws {
        let parts = try PrivateSpend.Destination.transfer(try TransferVectors.recipient()).parts(moving: 7, of: asset)

        #expect(parts.transfer?.amount == 7)
        #expect(parts.withdrawal == nil)
    }

    @Test
    func `Funded transfers withdraw SOL to the recipient's signing address`() throws {
        let recipient = try TransferVectors.recipient()

        let parts = try PrivateSpend.Destination.fundedTransfer(recipient, publicLamports: 5).parts(moving: 7, of: .nativeSOL)

        #expect(parts.transfer?.amount == 7)
        #expect(parts.withdrawal == ExternalData.Withdrawal(recipient: recipient.signingAddress, amount: 5, asset: .nativeSOL))
    }
}
