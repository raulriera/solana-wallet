import Foundation
import Testing
import Transactions

struct MessageBuilderTests {
    @Test
    func `SOL transfers preserve the payment and separate service tip`() throws {
        let sender = try Address(MessageFixture.sender)
        let transfer = try SystemProgram.transfer(from: sender, to: Address(MessageFixture.recipient), lamports: 1_000_000)
        let tip = try SystemProgram.transfer(from: sender, to: Address("4ACfpUFoaSD9bfPdeu6DBt89gB6ENTeHBXCAi87NhDEE"),
                               lamports: 5_000)
        let configuration = try Configuration(priorityFeeLamports: 5_000, computeUnitLimit: 20_000,
                                               loadedAccountsDataSizeLimit: 65_536)
        let message = try MessageBuilder().message(instructions: [transfer, tip], payer: sender,
            recentBlockhash: "11111111111111111111111111111111", configuration: configuration)
        let signature = Data(repeating: 0, count: 64)
        let actual = try TransactionDecoder().decode(message + signature)
        let expected = try TransactionDecoder().decode(#require(Data(base64Encoded: "gQEAAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIEMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2Au7nuJKk74pEqr+XDMDjfq9yZ2dRcMHWmc0xJ0SWxUP36MCIdgv94d3c8ywX8gm4JC7lKq8TH6zYjQ6ixtCwbyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACIEwAAAAAAACBOAAAAAAEAAwIMAAMCDAAAAgIAAABAQg8AAAAAAAABAgAAAIgTAAAAAAAA")) + signature)

        #expect(actual.requests == expected.requests)
        #expect(actual.lifetimeSpecifier == expected.lifetimeSpecifier)
        #expect(actual.accounts.filter(\.isSigner) == expected.accounts.filter(\.isSigner))
        try #require(actual.instructions.count == expected.instructions.count)
        for (instruction, reference) in zip(actual.instructions, expected.instructions) {
            #expect(actual.accounts[instruction.programIndex] == expected.accounts[reference.programIndex])
            #expect(instruction.accountIndices.map { actual.accounts[$0] }
                    == reference.accountIndices.map { expected.accounts[$0] })
            #expect(instruction.data == reference.data)
        }
    }

    @Test
    func `Empty instruction compositions are rejected`() throws {
        #expect(throws: ValidationError.invalidMessage) {
            try MessageBuilder().message(instructions: [], payer: Address(MessageFixture.sender),
                recentBlockhash: MessageFixture.zeroBlockhash, configuration: MessageFixture.transfers[0].configuration())
        }
    }

    @Test(arguments: MessageFixture.transfers)
    func `SOL transfers match Solana SDK V1 message bytes`(_ fixture: MessageFixture) throws {
        let builder = MessageBuilder()
        let transfer = try SystemProgram.transfer(from: Address(MessageFixture.sender), to: Address(MessageFixture.recipient), lamports: fixture.lamports)
        let message = try builder.message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: fixture.blockhash,
                                          configuration: fixture.configuration())

        #expect(message == Data(base64Encoded: fixture.message))
    }

    @Test
    func `Self transfers reuse the signer and preserve maximum lamport values`() throws {
        let fixture = MessageFixture.selfTransfer
        let sender = try Address(MessageFixture.sender)
        let transfer = try SystemProgram.transfer(from: sender, to: sender, lamports: fixture.lamports)
        let message = try MessageBuilder().message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: fixture.blockhash,
                                                   configuration: fixture.configuration())

        #expect(message == Data(base64Encoded: fixture.message))
    }

    @Test
    func `Message construction rejects an invalid recent blockhash`() throws {
        let transfer = try SystemProgram.transfer(from: Address(MessageFixture.sender), to: Address(MessageFixture.recipient), lamports: 1)
        let configuration = try MessageFixture.transfers[0].configuration()

        #expect(throws: ValidationError.invalidBlockhash) {
            try MessageBuilder().message(instructions: [transfer], payer: transfer.accounts[0].address, recentBlockhash: "invalid", configuration: configuration)
        }
    }
}
