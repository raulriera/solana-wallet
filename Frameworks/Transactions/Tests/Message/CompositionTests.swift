import Foundation
import Testing
import Transactions

/// Verifies generic composition against independently compiled Kit 8.4.0 instructions.
struct CompositionTests {
    /// Verifies distinct payer and authorities, merged privileges, and duplicate arguments.
    @Test
    func `Composed programs preserve ordered instructions and every required signer`() throws {
        let payer = try Address(MessageFixture.sender)
        let authority = try Address(MessageFixture.recipient)
        let readonlySigner = try Address("So11111111111111111111111111111111111111112")
        let program = try Address(DecodingFixture.program)
        let instructions = try [
            SystemProgram.transfer(from: authority, to: payer, lamports: 1),
            MemoProgram.memo("composed", signers: [readonlySigner]),
            Instruction(program: program, accounts: [
                .init(address: authority, isSigner: false, isWritable: false),
                .init(address: payer, isSigner: false, isWritable: false),
                .init(address: authority, isSigner: false, isWritable: false),
            ], data: Data([255, 0, 127])),
        ]
        let message = try MessageBuilder().message(instructions: instructions, payer: payer,
            recentBlockhash: MessageFixture.zeroBlockhash,
            configuration: Configuration(priorityFeeLamports: 0, computeUnitLimit: 200_000,
                                         loadedAccountsDataSizeLimit: 65_536))
        let actual = try TransactionDecoder().decode(TransactionBuilder().simulationTransaction(for: message))
        let expected = try TransactionDecoder().decode(base64: "gQMBAg8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMFMhz6Wt0YXoiTpf2IAT7E1+Ei3tRjVMrf9Q2VY5XnW2B+jAiHYL/eHd3PMsF/IJuCQu5SqvEx+s2I0OosbQsG8gabiFf+q4GE+2h/Y0YYwDXaxDncGus7VZig8AAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFSlNamSkhBk0k6HFg2jh8fDW13bySu4HkH6hAQQVEjQAAAAAAAAAAQA0DAAAAAQADAgwABAEIAAQDAwABAAIAAAABAAAAAAAAAAJjb21wb3NlZAEAAf8AfwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==")

        #expect(actual.accounts.first?.address == payer)
        #expect(actual.accounts.filter(\.isSigner) == expected.accounts.filter(\.isSigner))
        #expect(actual.signatures == Array(repeating: Data(repeating: 0, count: 64), count: 3))
        #expect(actual.requests == expected.requests)
        try #require(actual.instructions.count == expected.instructions.count)
        for (instruction, reference) in zip(actual.instructions, expected.instructions) {
            #expect(actual.accounts[instruction.programIndex] == expected.accounts[reference.programIndex])
            #expect(instruction.accountIndices.map { actual.accounts[$0] }
                    == reference.accountIndices.map { expected.accounts[$0] })
            #expect(instruction.data == reference.data)
        }
    }

    /// Verifies signature space counts against the same atomic transaction limit as instructions.
    @Test
    func `Additional signatures can make an otherwise fitting transaction too large`() throws {
        let payer = try Address(MessageFixture.sender)
        let authority = try Address(MessageFixture.recipient)
        let instruction = Instruction(program: try Address(DecodingFixture.program),
            accounts: [.init(address: authority, isSigner: true, isWritable: false)],
            data: Data(repeating: 0, count: 3_820))
        #expect(throws: ValidationError.invalidMessage) {
            try MessageBuilder().message(instructions: [instruction], payer: payer,
                recentBlockhash: MessageFixture.zeroBlockhash,
                configuration: MessageFixture.transfers[0].configuration())
        }
    }

    /// Verifies an instruction cannot make an invoked program writable through another invocation.
    @Test
    func `Conflicting program permissions are rejected across the whole composition`() throws {
        let payer = try Address(MessageFixture.sender)
        let program = try Address(DecodingFixture.program)
        let instructions = try [
            MemoProgram.memo("first"),
            Instruction(program: Address("11111111111111111111111111111111"),
                accounts: [.init(address: program, isSigner: false, isWritable: true)]),
        ]
        #expect(throws: ValidationError.invalidMessage) {
            try MessageBuilder().message(instructions: instructions, payer: payer,
                recentBlockhash: MessageFixture.zeroBlockhash,
                configuration: MessageFixture.transfers[0].configuration())
        }
    }
}
