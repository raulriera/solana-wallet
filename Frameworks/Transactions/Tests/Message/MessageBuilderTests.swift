import Foundation
import Testing
import Transactions

/// Verifies public message construction against independently generated Solana SDK bytes.
struct MessageBuilderTests {
    /// Verifies payment and tip semantics against independent Solana Kit 8.4 messages.
    ///
    /// - Parameters:
    ///   - tipLamports: The service tip encoded after the ordinary payment.
    ///   - expectedMessage: The independently encoded unsigned V1 message.
    @Test(arguments: [
        (UInt64(5_000), "gQEAAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIEMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2Au7nuJKk74pEqr+XDMDjfq9yZ2dRcMHWmc0xJ0SWxUP36MCIdgv94d3c8ywX8gm4JC7lKq8TH6zYjQ6ixtCwbyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACIEwAAAAAAACBOAAAAAAEAAwIMAAMCDAAAAgIAAABAQg8AAAAAAAABAgAAAIgTAAAAAAAA"),
        (UInt64(1_000_000), "gQEAAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIEMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2Au7nuJKk74pEqr+XDMDjfq9yZ2dRcMHWmc0xJ0SWxUP36MCIdgv94d3c8ywX8gm4JC7lKq8TH6zYjQ6ixtCwbyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACIEwAAAAAAACBOAAAAAAEAAwIMAAMCDAAAAgIAAABAQg8AAAAAAAABAgAAAEBCDwAAAAAA"),
    ])
    func `SOL transfers preserve the payment and separate service tip`(tipLamports: UInt64, expectedMessage: String) throws {
        let sender = try Address(MessageFixture.sender)
        let transfer = try SystemProgram.transfer(from: sender, to: Address(MessageFixture.recipient), lamports: 1_000_000)
        let tip = try SystemProgram.transfer(from: sender, to: Address("4ACfpUFoaSD9bfPdeu6DBt89gB6ENTeHBXCAi87NhDEE"),
                               lamports: tipLamports)
        let configuration = try Configuration(priorityFeeLamports: 5_000, computeUnitLimit: 20_000,
                                               loadedAccountsDataSizeLimit: 65_536)
        let message = try MessageBuilder().message(instructions: [transfer, tip], payer: sender,
            recentBlockhash: "11111111111111111111111111111111", configuration: configuration)
        let signature = Data(repeating: 0, count: 64)
        let actual = try TransactionDecoder().decode(message + signature)
        let expected = try TransactionDecoder().decode(#require(Data(base64Encoded: expectedMessage)) + signature)

        #expect(actual.requests == expected.requests)
        #expect(actual.lifetimeSpecifier == expected.lifetimeSpecifier)
        #expect(actual.accounts.filter(\.isSigner) == expected.accounts.filter(\.isSigner))
        try #require(actual.instructions.count == expected.instructions.count)
        // Kit orders writable accounts differently; compare the resolved instructions.
        for (instruction, reference) in zip(actual.instructions, expected.instructions) {
            #expect(actual.accounts[instruction.programIndex] == expected.accounts[reference.programIndex])
            #expect(instruction.accountIndices.map { actual.accounts[$0] }
                    == reference.accountIndices.map { expected.accounts[$0] })
            #expect(instruction.data == reference.data)
        }
    }

    /// Verifies an empty composition cannot produce a wallet transaction.
    @Test
    func `Empty instruction compositions are rejected`() throws {
        #expect(throws: ValidationError.invalidMessage) {
            try MessageBuilder().message(instructions: [], payer: Address(MessageFixture.sender),
                recentBlockhash: MessageFixture.zeroBlockhash, configuration: MessageFixture.transfers[0].configuration())
        }
    }

    /// Verifies V1 headers, accounts, configuration, and transfer data as a complete message.
    ///
    /// - Parameter fixture: A public example generated with Solana Kit 8.0.0.
    @Test(arguments: MessageFixture.transfers)
    func `SOL transfers match Solana SDK V1 message bytes`(_ fixture: MessageFixture) throws {
        let builder: any MessageBuilding = MessageBuilder()
        let transfer = try SystemProgram.transfer(from: Address(MessageFixture.sender), to: Address(MessageFixture.recipient), lamports: fixture.lamports)
        let message = try builder.message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: fixture.blockhash,
                                          configuration: fixture.configuration())

        #expect(message == Data(base64Encoded: fixture.message))
    }

    /// Verifies account deduplication and lossless encoding of UInt64 amounts and fees.
    @Test
    func `Self transfers reuse the signer and preserve maximum lamport values`() throws {
        let fixture = MessageFixture.selfTransfer
        let sender = try Address(MessageFixture.sender)
        let transfer = try SystemProgram.transfer(from: sender, to: sender, lamports: fixture.lamports)
        let message = try MessageBuilder().message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: fixture.blockhash,
                                                   configuration: fixture.configuration())

        #expect(message == Data(base64Encoded: fixture.message))
    }

    /// Verifies malformed blockhashes fail before message bytes are returned.
    @Test
    func `Message construction rejects an invalid recent blockhash`() throws {
        let transfer = try SystemProgram.transfer(from: Address(MessageFixture.sender), to: Address(MessageFixture.recipient), lamports: 1)
        let configuration = try MessageFixture.transfers[0].configuration()

        #expect(throws: ValidationError.invalidBlockhash) {
            try MessageBuilder().message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: "invalid", configuration: configuration)
        }
    }
}
