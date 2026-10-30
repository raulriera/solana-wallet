import Foundation
import Testing
import Transactions

struct TransactionDecoderTests {
    @Test
    func `Base64 imports preserve the complete V1 transaction`() throws {
        let decoder: any TransactionDecoding = TransactionDecoder()

        let transaction = try decoder.decode(base64: DecodingFixture.wire)

        #expect(transaction == (try decoder.decode(DecodingFixture.transaction())))
        #expect(transaction.serializedRepresentation == (try DecodingFixture.transaction()))
    }

    @Test(arguments: [
        "!", " \(DecodingFixture.wire)", String(repeating: "A", count: 5_465)
    ])
    func `Invalid Base64 imports cannot become transactions`(_ input: String) throws {
        #expect(throws: ValidationError.invalidTransaction) { try TransactionDecoder().decode(base64: input) }
    }

    @Test(arguments: [false, true])
    func `V1 inspection preserves signer roles, instruction order, and exact signed bytes`(usesSlice: Bool) throws {
        let original = try DecodingFixture.transaction()
        var input = original
        if usesSlice {
            input.insert(0xff, at: input.startIndex)
            input = input.dropFirst()
            #expect(input.startIndex != 0)
        }
        let decoder: any TransactionDecoding = TransactionDecoder()

        let transaction = try decoder.decode(input)

        #expect(transaction.message == (try #require(Data(base64Encoded: DecodingFixture.message))))
        #expect(transaction.lifetimeSpecifier == MessageFixture.zeroBlockhash)
        #expect(transaction.accounts.map(\.address.value) == [
            MessageFixture.sender, MessageFixture.recipient, SignedTransferFixture.sender, DecodingFixture.program
        ])
        #expect(transaction.accounts.map(\.isSigner) == [true, true, false, false])
        #expect(transaction.accounts.map(\.isWritable) == [true, false, true, false])
        #expect(transaction.requests == .init(priorityFeeLamports: UInt64.max, computeUnitLimit: 20_000,
                                              loadedAccountsDataSizeLimit: 65_536, heapSize: 32_768))
        #expect(transaction.instructions == [
            .init(programIndex: 3, accountIndices: [0, 1, 2, 1], data: Data([1, 2, 3])),
            .init(programIndex: 3, accountIndices: [2], data: Data([4, 5]))
        ])
        #expect(transaction.signatures == [Data(repeating: 0, count: 64), Data(repeating: 0x55, count: 64)])
        #expect(transaction.message + transaction.signatures.reduce(Data(), +) == original)
    }

    @Test(arguments: [
        nil, UInt32(0), UInt32.max
    ])
    func `Resource requests preserve omission, explicit zero, and unclamped values`(_ value: UInt32?) throws {
        var input = try DecodingFixture.transaction()
        let values = value.map { Data(repeating: $0 == 0 ? 0 : 0xff, count: 16) } ?? Data()
        input.replaceSubrange(DecodingFixture.requestsStart..<DecodingFixture.headersStart, with: values)
        input.replaceSubrange(4..<8, with: [value == nil ? 0 : 15, 0, 0, 0])

        let transaction = try TransactionDecoder().decode(input)

        let fee: UInt64? = value.map { $0 == 0 ? 0 : UInt64.max }
        #expect(transaction.requests == .init(priorityFeeLamports: fee, computeUnitLimit: value,
                                              loadedAccountsDataSizeLimit: value, heapSize: nil))
        #expect(transaction.instructions.last?.data == Data([4, 5]))
    }

    @Test
    func `A 4096-byte V1 envelope retains its complete instruction payload`() throws {
        var input = try DecodingFixture.transaction()
        let extra = 4_096 - input.count
        let payloadSize = 2 + extra
        input.insert(contentsOf: repeatElement(UInt8(7), count: extra), at: input.count - 128)
        input.replaceSubrange(196..<198, with: [UInt8(truncatingIfNeeded: payloadSize), UInt8(payloadSize >> 8)])

        let transaction = try TransactionDecoder().decode(input)

        #expect(input.count == 4_096)
        #expect(transaction.instructions.last?.data == Data([4, 5]) + Data(repeating: 7, count: extra))
        #expect(transaction.signatures.last == Data(repeating: 0x55, count: 64))
    }

    @Test(arguments: 0..<(try DecodingFixture.transaction()).count)
    func `Incomplete envelopes are rejected`(length: Int) throws {
        let input = try DecodingFixture.transaction()
        #expect(throws: ValidationError.invalidTransaction) {
            try TransactionDecoder().decode(Data(input.prefix(length)))
        }
    }

    @Test(arguments: [try DecodingFixture.transaction() + Data([0]), Data(repeating: 0, count: 4_097)])
    func `Extended and oversized envelopes are rejected`(invalid: Data) {
        #expect(throws: ValidationError.invalidTransaction) { try TransactionDecoder().decode(invalid) }
    }

    @Test(arguments: [
        "no signer", "too many signers", "readonly payer", "overlapping readonly accounts",
        "too many accounts", "too many instructions", "duplicate address", "program outside accounts",
        "payer as program", "instruction account outside accounts", "oversized payload length"
    ])
    func `Invalid signer layouts and account references cannot be inspected`(_ change: String) throws {
        var input = try DecodingFixture.transaction()
        switch change {
        case "no signer": input[1] = 0
        case "too many signers": input[1] = 13
        case "readonly payer": input[2] = 2
        case "overlapping readonly accounts": input[3] = 3
        case "too many accounts": input[41] = 65
        case "too many instructions": input[40] = 65
        case "duplicate address": input.replaceSubrange(74..<106, with: input[42..<74])
        case "program outside accounts": input[DecodingFixture.headersStart] = 4
        case "payer as program": input[DecodingFixture.headersStart] = 0
        case "instruction account outside accounts": input[DecodingFixture.payloadsStart] = 4
        default: input.replaceSubrange(192..<194, with: [0xff, 0xff])
        }

        #expect(throws: ValidationError.invalidTransaction) { try TransactionDecoder().decode(input) }
    }

    @Test(arguments: [UInt8(1), 0x80, 0x82])
    func `Legacy, V0, and unknown transaction versions are rejected`(_ version: UInt8) throws {
        var input = try DecodingFixture.transaction()
        input[0] = version

        #expect(throws: ValidationError.unsupportedVersion) { try TransactionDecoder().decode(input) }
    }

    @Test(arguments: [UInt32(1), 2, 32, 0x80000000])
    func `Partial fees and unknown configuration bits are rejected`(_ mask: UInt32) throws {
        var input = try DecodingFixture.transaction()
        input.replaceSubrange(4..<8, with: (0..<4).map { UInt8(truncatingIfNeeded: mask >> ($0 * 8)) })
        let error: ValidationError = mask <= 2 ? .invalidTransaction : .unsupportedConfiguration

        #expect(throws: error) { try TransactionDecoder().decode(input) }
    }

    @Test
    func `An unaligned encoded heap request is rejected`() throws {
        var input = try DecodingFixture.transaction()
        input[186] = 1

        #expect(throws: ValidationError.invalidHeapSize) { try TransactionDecoder().decode(input) }
    }
}
