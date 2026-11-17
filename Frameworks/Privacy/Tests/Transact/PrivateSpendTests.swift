import Testing
import Transactions
@testable import Privacy

struct PrivateSpendTests {
    @Test
    func `Withdrawals pay SOL to the owner and a token to the owner's token account, which they open`() throws {
        let owner = try Address(TransferVectors.recipientSigningAddress)
        let payer = try Address(TransferVectors.senderSigningAddress)
        let destination = PrivateSpend.Destination.withdrawal(owner)
        let tokenAccount = try TokenProgram.token.associatedAccount(owner: owner, mint: PrivateToken.usdc.mint)
        let opening = try AssociatedTokenProgram.createIdempotent(owner: owner, mint: PrivateToken.usdc.mint,
                                                                  program: .token, payer: payer)

        let sol = try destination.parts(moving: 1, of: .nativeSOL, paidBy: payer)
        let token = try destination.parts(moving: 1, of: .token(.usdc), paidBy: payer)

        #expect(sol.withdrawal == ExternalData.Withdrawal(recipient: owner, amount: 1, asset: .nativeSOL))
        #expect(sol.openings.isEmpty)
        #expect(token.withdrawal == ExternalData.Withdrawal(recipient: tokenAccount, amount: 1, asset: .token(.usdc)))
        #expect(token.openings.map(\.account) == [tokenAccount])
        #expect(token.openings.map(\.instruction) == [opening])
    }

    @Test(arguments: [PrivateAsset.nativeSOL, .token(.usdc)])
    func `Transfers carry no withdrawal and open no account`(asset: PrivateAsset) throws {
        let parts = try PrivateSpend.Destination.transfer(try TransferVectors.recipient())
            .parts(moving: 7, of: asset, paidBy: Address(TransferVectors.senderSigningAddress))

        #expect(parts.transfer?.amount == 7)
        #expect(parts.withdrawal == nil)
        #expect(parts.openings.isEmpty)
    }

    @Test
    func `Funded transfers withdraw SOL to the recipient's signing address`() throws {
        let recipient = try TransferVectors.recipient()

        let parts = try PrivateSpend.Destination.fundedTransfer(recipient, publicLamports: 5)
            .parts(moving: 7, of: .nativeSOL, paidBy: Address(TransferVectors.senderSigningAddress))

        #expect(parts.transfer?.amount == 7)
        #expect(parts.withdrawal == ExternalData.Withdrawal(recipient: recipient.signingAddress, amount: 5, asset: .nativeSOL))
        #expect(parts.openings.isEmpty)
    }
}
