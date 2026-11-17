import Foundation
import Testing
import Transactions

struct TokenTransferTests {
    @Test(arguments: TokenFixtures.transfers)
    func `Token transfers match SDK instructions and account privileges`(_ fixture: TokenFixture) throws {
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                                         mint: fixture.mint(), source: fixture.source(),
                                         destination: fixture.createsDestination ? nil : fixture.target(), amount: fixture.amount)
        let builder = MessageBuilder()
        let message = try builder.message(instructions: transfer.instructions(), payer: transfer.sender, recentBlockhash: MessageFixture.zeroBlockhash,
                                          configuration: configuration())
        let decoder = TransactionDecoder()
        let result = try decoder.decode(TransactionBuilder().simulationTransaction(for: message))
        let reference = try decoder.decode(base64: fixture.wire)
        #expect(transfer.destination.value == fixture.destination)
        #expect(transfer.expectedFee == nil)
        #expect(result.requests == reference.requests)
        #expect(result.lifetimeSpecifier == reference.lifetimeSpecifier)
        #expect(result.accounts.first == reference.accounts.first)
        #expect(result.instructions.count == reference.instructions.count)
        for (actual, expected) in zip(result.instructions, reference.instructions) {
            #expect(result.accounts[actual.programIndex] == reference.accounts[expected.programIndex])
            #expect(actual.accountIndices.map { result.accounts[$0] } == expected.accountIndices.map { reference.accounts[$0] })
            #expect(actual.data == expected.data)
        }
    }

    @Test(arguments: [
        (UInt64(1), UInt64(99), UInt64(1), 0),
        (10_001, 99, 26, 1), (10_001, 100, 50, 2), (.max, 100, 50, 3),
    ])
    func `Token-2022 transfers assert the epoch fee with exact rounding and caps`(
        amount: UInt64, epoch: UInt64, fee: UInt64, fixtureIndex: Int
    ) throws {
        let fixture = TokenFixtures.transfers[2]
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                                         mint: fixture.mint(TokenFixtures.feeMint), source: fixture.source(Data(base64Encoded: TokenFixtures.feeSource)),
                                         destination: fixture.target(TokenFixtures.feeDestination), amount: amount, epoch: epoch)
        let message = try MessageBuilder().message(instructions: transfer.instructions(), payer: transfer.sender, recentBlockhash: MessageFixture.zeroBlockhash,
                                                   configuration: configuration())
        let result = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
        #expect(transfer.expectedFee == fee)
        try #require(TokenFixtures.feeInstructions.indices.contains(fixtureIndex))
        #expect(result.instructions.last?.data == Data(base64Encoded: TokenFixtures.feeInstructions[fixtureIndex]))
    }

    @Test
    func `Fee-bearing transfers require an observed ledger epoch`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.epochRequired) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(TokenFixtures.feeMint), source: fixture.source(),
                              destination: fixture.target(), amount: 1)
        }
    }

    @Test
    func `Memo-required transfers place the memo immediately before the token instruction`() throws {
        let fixture = TokenFixtures.transfers[2]
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                                         mint: fixture.mint(), source: fixture.source(),
                                         destination: fixture.target(TokenFixtures.memoAccount), amount: 1, memo: "Invoice 42")
        let message = try MessageBuilder().message(instructions: transfer.instructions(), payer: transfer.sender, recentBlockhash: MessageFixture.zeroBlockhash,
                                                   configuration: configuration())
        let result = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
        try #require(result.instructions.count == 2)
        #expect(result.instructions[0].data == Data("Invoice 42".utf8))
        #expect(result.accounts[result.instructions[0].programIndex].address.value == "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr")
        let memoSigner = try #require(result.instructions[0].accountIndices.first)
        #expect(result.accounts[memoSigner].isSigner)
        #expect(result.instructions[1].data.first == 12)
    }

    @Test
    func `Memo-required transfers reject a missing memo`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.memoRequired) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(), source: fixture.source(),
                              destination: fixture.target(TokenFixtures.memoAccount), amount: 1)
        }
    }

    @Test
    func `Token transfers reject a mint without account data`() throws {
        let fixture = TokenFixtures.transfers[0]
        let decoded = try fixture.mint()
        let facts = Mint(address: decoded.address, program: decoded.program, decimals: decoded.decimals, metadata: nil)
        #expect(throws: TokenError.invalidAccount) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: facts, source: fixture.source(), destination: nil, amount: 1)
        }
    }

    @Test(arguments: Mismatch.allCases)
    func `Token transfers reject accounts that don't match the transfer`(_ mismatch: Mismatch) throws {
        let fixture = TokenFixtures.transfers[mismatch == .destinationWithoutFeeExtension ? 2 : 0]
        var sender = try Address(TokenFixtures.sender)
        var recipient = try Address(TokenFixtures.recipient)
        var mint = try fixture.mint()
        var source = try fixture.source()
        var destination: Token?
        switch mismatch {
        case .unownedSource: swap(&sender, &recipient)
        case .otherProgramsSource: mint = try TokenFixtures.transfers[2].mint()
        case .otherWalletsDestination: destination = try fixture.target(fixture.sourceData)
        case .mintRecipient: recipient = try Address(TokenFixtures.mint)
        case .destinationWithoutFeeExtension:
            mint = try fixture.mint(TokenFixtures.feeMint)
            source = try fixture.source(Data(base64Encoded: TokenFixtures.feeSource))
            destination = try fixture.target()
        }

        #expect(throws: TokenError.accountMismatch) {
            try TokenTransfer(sender: sender, recipient: recipient, mint: mint, source: source,
                              destination: destination, amount: 1, epoch: 100)
        }
    }

    @Test(arguments: TokenFixtures.transfers.filter { !$0.createsDestination })
    func `Token transfers send directly to another token account the recipient owns`(_ fixture: TokenFixture) throws {
        let account = try Token(address: Address("7HYrVp9r32ggmv4UHmNh8EKJjg91Cqf8CF2WfT684eXb"),
                                       programAddress: Address(fixture.program),
                                       data: #require(Data(base64Encoded: fixture.destinationData)))
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                                         mint: fixture.mint(), source: fixture.source(), destination: account, amount: 1)
        let instructions = try transfer.instructions()

        #expect(transfer.destination == account.address)
        #expect(!transfer.createsDestination)
        try #require(instructions.count == 1)
        #expect(instructions[0].accounts[2].address == account.address)
    }

    @Test
    func `Token transfers reject an amount above the source balance`() throws {
        let fixture = TokenFixtures.transfers[0]
        var bytes = try #require(Data(base64Encoded: fixture.sourceData))
        bytes.replaceSubrange(64..<72, with: repeatElement(UInt8(0), count: 8))
        #expect(throws: TokenError.insufficientBalance) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(), source: fixture.source(bytes), destination: nil, amount: 1)
        }
    }

    @Test
    func `New token accounts reject a mint whose default account state is frozen`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.frozenAccount) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(TokenFixtures.frozenMint), source: fixture.source(), destination: nil, amount: 1)
        }
    }

    @Test
    func `Transfers report a hook extension that requires additional accounts`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.unsupportedExtension(14)) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(TokenFixtures.hookMint), source: fixture.source(), destination: nil, amount: 1)
        }
    }

    @Test(arguments: [false, true])
    func `Mint decoding rejects truncated and duplicate extensions`(duplicatesExtension: Bool) throws {
        let fixture = TokenFixtures.transfers[2]
        let bytes = try #require(Data(base64Encoded: TokenFixtures.feeMint))
        let data = duplicatesExtension ? bytes + bytes.dropFirst(166) : Data(bytes.dropLast())
        #expect(throws: TokenError.invalidAccount) {
            try Mint(address: Address(TokenFixtures.mint), programAddress: Address(fixture.program), data: data)
        }
    }

    private func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 0, computeUnitLimit: 200_000, loadedAccountsDataSizeLimit: 65_536)
    }

    enum Mismatch: CaseIterable {
        case unownedSource
        case otherProgramsSource
        case otherWalletsDestination
        case mintRecipient
        case destinationWithoutFeeExtension
    }
}
