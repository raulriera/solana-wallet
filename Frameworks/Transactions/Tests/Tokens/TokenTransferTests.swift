import Foundation
import Testing
import Transactions

/// Verifies both token programs through the same public transfer construction API.
struct TokenTransferTests {
    /// Verifies a service payment follows the token instruction and shares the fee payer.
    ///
    /// - Parameter fixture: A transfer with idempotent ATA creation for either token program.
    @Test(arguments: TokenFixtures.transfers.filter(\.createsDestination))
    func `Token transfers include the exact SOL service tip after the checked transfer`(_ fixture: TokenFixture) throws {
        let sender = try Address(TokenFixtures.sender)
        let transfer = try TokenTransfer(sender: sender, recipient: Address(TokenFixtures.recipient),
                                         mint: fixture.mint(), source: fixture.source(), destination: nil, amount: 1)
        let tip = try SystemProgram.transfer(from: sender, to: Address(TokenFixtures.recipient), lamports: 5_000)
        let builder: any MessageBuilding = MessageBuilder()
        let message = try builder.message(instructions: transfer.instructions() + [tip], payer: transfer.sender, recentBlockhash: MessageFixture.zeroBlockhash,
                                          configuration: configuration())
        let transaction = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))

        try #require(transaction.instructions.count == 3)
        let instruction = transaction.instructions[2]
        #expect(transaction.instructions[1].data.first == 12)
        #expect(transaction.accounts[instruction.programIndex].address.value == "11111111111111111111111111111111")
        #expect(instruction.accountIndices.map { transaction.accounts[$0].address } == [sender, tip.accounts[1].address])
        #expect(instruction.data == Data([2, 0, 0, 0, 0x88, 0x13, 0, 0, 0, 0, 0, 0]))
        #expect(transaction.accounts.filter(\.isSigner).map(\.address) == [sender])
    }

    /// Verifies transfers and idempotent ATA creation against independent SDK instructions.
    ///
    /// - Parameter fixture: An original-token or Token-2022 example with an existing or absent ATA.
    @Test(arguments: TokenFixtures.transfers)
    func `Token transfers match SDK instructions and account privileges`(_ fixture: TokenFixture) throws {
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                                         mint: fixture.mint(), source: fixture.source(),
                                         destination: fixture.createsDestination ? nil : fixture.target(), amount: fixture.amount)
        let builder: any MessageBuilding = MessageBuilder()
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
        // Account ordering can differ between compilers. Compare instructions by
        // resolved address and role, retaining each instruction's account order.
        for (actual, expected) in zip(result.instructions, reference.instructions) {
            #expect(result.accounts[actual.programIndex] == reference.accounts[expected.programIndex])
            #expect(actual.accountIndices.map { result.accounts[$0] } == expected.accountIndices.map { reference.accounts[$0] })
            #expect(actual.data == expected.data)
        }
    }

    /// Verifies the fee boundary, ceiling division, maximum cap, and UInt64 overflow safety.
    /// - Parameters:
    ///   - amount: The transfer amount in base units.
    ///   - epoch: The ledger epoch selecting the fee schedule.
    ///   - fee: The expected fee after rounding and capping.
    ///   - fixtureIndex: The corresponding independent SDK instruction.
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

    /// Verifies a missing epoch cannot silently select a fee schedule.
    @Test
    func `Fee-bearing transfers require an observed ledger epoch`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.epochRequired) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(TokenFixtures.feeMint), source: fixture.source(),
                              destination: fixture.target(), amount: 1)
        }
    }

    /// Verifies a fee mint cannot use an existing account without withheld-fee storage.
    @Test
    func `Fee-bearing transfers reject a destination missing its required fee extension`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.accountMismatch) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(TokenFixtures.feeMint),
                              source: fixture.source(Data(base64Encoded: TokenFixtures.feeSource)),
                              destination: fixture.target(), amount: 1, epoch: 100)
        }
    }

    /// Verifies incoming memo requirements produce a signed memo immediately before the transfer.
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

    /// Verifies a required memo cannot be omitted even when token funds are sufficient.
    @Test
    func `Memo-required transfers reject a missing memo`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.memoRequired) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(), source: fixture.source(),
                              destination: fixture.target(TokenFixtures.memoAccount), amount: 1)
        }
    }

    /// Verifies a different token authority cannot be substituted by the caller.
    @Test
    func `Token transfers reject a sender who does not own the source account`() throws {
        let fixture = TokenFixtures.transfers[0]
        #expect(throws: TokenError.accountMismatch) {
            try TokenTransfer(sender: Address(TokenFixtures.recipient), recipient: Address(TokenFixtures.sender),
                              mint: fixture.mint(), source: fixture.source(), destination: nil, amount: 1)
        }
    }

    /// Verifies program selection comes from the mint and account observations together.
    @Test
    func `Token transfers reject accounts belonging to another token program`() throws {
        #expect(throws: TokenError.accountMismatch) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: TokenFixtures.transfers[2].mint(), source: TokenFixtures.transfers[0].source(),
                              destination: nil, amount: 1)
        }
    }

    /// Verifies the recipient's address cannot be paired with another wallet's account state.
    @Test
    func `Token transfers reject a destination controlled by another wallet`() throws {
        let fixture = TokenFixtures.transfers[0]
        let wrongOwner = try TokenAccount(address: Address(fixture.destination), programOwner: Address(fixture.program),
                                          data: #require(Data(base64Encoded: fixture.sourceData)))
        #expect(throws: TokenError.accountMismatch) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(), source: fixture.source(), destination: wrongOwner, amount: 1)
        }
    }

    /// Verifies a token account the recipient owns receives the tokens even when it isn't the associated account.
    ///
    /// - Parameter fixture: An original-token or Token-2022 example with an existing destination.
    @Test(arguments: TokenFixtures.transfers.filter { !$0.createsDestination })
    func `Token transfers send directly to another token account the recipient owns`(_ fixture: TokenFixture) throws {
        let account = try TokenAccount(address: Address("7HYrVp9r32ggmv4UHmNh8EKJjg91Cqf8CF2WfT684eXb"),
                                       programOwner: Address(fixture.program),
                                       data: #require(Data(base64Encoded: fixture.destinationData)))
        let transfer = try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                                         mint: fixture.mint(), source: fixture.source(), destination: account, amount: 1)
        let instructions = try transfer.instructions()

        #expect(transfer.destination == account.address)
        #expect(!transfer.createsDestination)
        try #require(instructions.count == 1)
        #expect(instructions[0].accounts[2].address == account.address)
    }

    /// Verifies tokens can't go to an associated account that the mint itself owns.
    ///
    /// - Parameter fixture: An original-token or Token-2022 example without a destination.
    @Test(arguments: TokenFixtures.transfers.filter(\.createsDestination))
    func `Token transfers reject the mint as the recipient`(_ fixture: TokenFixture) throws {
        #expect(throws: TokenError.accountMismatch) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.mint),
                              mint: fixture.mint(), source: fixture.source(), destination: nil, amount: 1)
        }
    }

    /// Verifies an observed source balance cannot be exceeded locally.
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

    /// Verifies a mint's default-frozen state prevents constructing an unusable new account.
    @Test
    func `New token accounts reject a mint whose default account state is frozen`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.frozenAccount) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(TokenFixtures.frozenMint), source: fixture.source(), destination: nil, amount: 1)
        }
    }

    /// Verifies hook programs cannot be silently dropped from transaction construction.
    @Test
    func `Transfers report a hook extension that requires additional accounts`() throws {
        let fixture = TokenFixtures.transfers[2]
        #expect(throws: TokenError.unsupportedExtension(14)) {
            try TokenTransfer(sender: Address(TokenFixtures.sender), recipient: Address(TokenFixtures.recipient),
                              mint: fixture.mint(TokenFixtures.hookMint), source: fixture.source(), destination: nil, amount: 1)
        }
    }

    /// Verifies truncated and duplicate TLV entries cannot influence transfer fee interpretation.
    /// - Parameter duplicatesExtension: Whether to duplicate an extension instead of truncating its bytes.
    @Test(arguments: [false, true])
    func `Mint decoding rejects truncated and duplicate extensions`(duplicatesExtension: Bool) throws {
        let fixture = TokenFixtures.transfers[2]
        let bytes = try #require(Data(base64Encoded: TokenFixtures.feeMint))
        let data = duplicatesExtension ? bytes + bytes.dropFirst(166) : Data(bytes.dropLast())
        #expect(throws: TokenError.invalidAccount) {
            try TokenMint(address: Address(TokenFixtures.mint), owner: Address(fixture.program), data: data)
        }
    }

    /// Supplies explicit resource requests shared by the independent SDK examples.
    ///
    /// - Returns: The same limits used by the fixture generator.
    /// - Throws: A validation error if fixture constants become invalid.
    private func configuration() throws -> Configuration {
        try Configuration(priorityFeeLamports: 0, computeUnitLimit: 200_000, loadedAccountsDataSizeLimit: 65_536)
    }
}
