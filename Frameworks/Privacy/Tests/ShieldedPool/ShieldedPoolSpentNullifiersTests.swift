import Foundation
import ModularArithmetic
import RPC
import Testing
import Transactions
@testable import Privacy

struct ShieldedPoolSpentNullifiersTests {
    private static let spent = [[UInt8](repeating: 0x21, count: 32), [UInt8](repeating: 0x22, count: 32)]

    private static let other = [UInt8](repeating: 0x23, count: 32)

    @Test(arguments: zip([16, 19, 21, 16] as [UInt8], [0, 7, 4, 8] as [UInt16]))
    func `Transact-layout instructions of the pool spend their inputs' nullifiers`(tag: UInt8, circuit: UInt16) throws {
        let data = SpendTransactions.transactData(spending: Self.spent, tag: tag, circuit: circuit)
        let transaction = try SpendTransactions.transaction(of: [(SpendTransactions.program, data)])

        #expect(try ShieldedPool.nullifiers(spentBy: transaction) == Set(Self.spent))
    }

    @Test(arguments: [nil, 2_000_000] as [UInt64?])
    func `Transacts with every optional field spend their inputs' nullifiers`(withdrawal: UInt64?) throws {
        let data = SpendTransactions.transactData(spending: Self.spent, withdrawing: withdrawal, includesOptionalFields: true)
        let transaction = try SpendTransactions.transaction(of: [(SpendTransactions.program, data)])

        #expect(try ShieldedPool.nullifiers(spentBy: transaction) == Set(Self.spent))
    }

    @Test(arguments: [17, 20] as [UInt8], [nil, 3] as [UInt8?])
    func `Merge instructions of the pool spend their nullifiers`(tag: UInt8, cacheSlot: UInt8?) throws {
        let data = SpendTransactions.mergeData(spending: Self.spent, tag: tag, cacheSlot: cacheSlot)
        let transaction = try SpendTransactions.transaction(of: [(SpendTransactions.program, data)])

        #expect(try ShieldedPool.nullifiers(spentBy: transaction) == Set(Self.spent))
    }

    @Test
    func `Spends that other programs invoke count with the top-level ones`() throws {
        let transaction = try SpendTransactions.transaction(
            of: [("ComputeBudget111111111111111111111111111111", [2])],
            inner: [
                (SpendTransactions.program, SpendTransactions.transactData(spending: Self.spent, tag: 19)),
                (SpendTransactions.program, SpendTransactions.mergeData(spending: [Self.other], tag: 20)),
            ]
        )

        #expect(try ShieldedPool.nullifiers(spentBy: transaction) == Set(Self.spent + [Self.other]))
    }

    @Test
    func `Every spend instruction of a transaction counts`() throws {
        let transaction = try SpendTransactions.transaction(of: [
            (SpendTransactions.program, SpendTransactions.transactData(spending: Self.spent)),
            (SpendTransactions.program, SpendTransactions.mergeData(spending: [Self.other])),
        ])

        #expect(try ShieldedPool.nullifiers(spentBy: transaction) == Set(Self.spent + [Self.other]))
    }

    @Test
    func `Spend data under another program spends nothing`() throws {
        let program = "11111111111111111111111111111111"
        let transaction = try SpendTransactions.transaction(
            of: [(program, SpendTransactions.transactData(spending: Self.spent))],
            inner: [(program, SpendTransactions.mergeData(spending: Self.spent))]
        )

        #expect(try ShieldedPool.nullifiers(spentBy: transaction).isEmpty)
    }

    @Test(arguments: [12, 13, 14, 15, 18] as [UInt8])
    func `Pool instructions that don't spend spend nothing`(tag: UInt8) throws {
        let data = [tag] + Array(SpendTransactions.transactData(spending: Self.spent).dropFirst())
        let transaction = try SpendTransactions.transaction(of: [(SpendTransactions.program, data), (SpendTransactions.program, [])])

        #expect(try ShieldedPool.nullifiers(spentBy: transaction).isEmpty)
    }

    @Test(arguments: malformedSpends())
    func `Spend data of an unknown layout fails the read`(data: [UInt8]) throws {
        let transaction = try SpendTransactions.transaction(
            of: [(SpendTransactions.program, SpendTransactions.transactData(spending: [Self.other]))],
            inner: [(SpendTransactions.program, data)]
        )

        #expect(throws: ShieldedPool.InstructionError.unknownLayout) { try ShieldedPool.nullifiers(spentBy: transaction) }
    }

    @Test(arguments: try InstructionVectors.load().transacts)
    func `Transacts that the app writes spend their inputs' nullifiers`(_ vector: InstructionVectors.Transact) throws {
        let utxos = try vector.inputs.map {
            try PlanFixtures.utxo(amount: $0.lamports, treeID: $0.treeID, blindingByte: $0.blindingByte, asset: .nativeSOL)
        }
        let plan = try PlanFixtures.plan(
            spending: utxos, of: .nativeSOL, transfer: vector.transferLamports,
            withdrawal: try vector.withdrawalLamports.map { try PlanFixtures.withdrawal($0, of: .nativeSOL) },
            outputTreeID: vector.outputTreeID, paddingInputs: vector.paddingInputs, paddingOutputs: vector.paddingOutputs
        )
        let proof = try TransactProof(a: Array(repeating: 1, count: 32), b: Array(repeating: 2, count: 128), c: Array(repeating: 3, count: 32))
        let contexts = vector.treeContexts.map { TreeContext(utxoTreeRootIndex: $0[0], nullifierTreeRootIndex: $0[1]) }
        let instruction = try plan.instruction(proof: proof, treeContexts: contexts)
        let transaction = try SpendTransactions.transaction(of: [(instruction.program.value, [UInt8](instruction.data))])

        let nullifiers = try ShieldedPool.nullifiers(spentBy: transaction)

        #expect(nullifiers == Set(plan.inputs.map(\.nullifier.bigEndianBytes)))
    }

    private static func malformedSpends() -> [[UInt8]] {
        let transact = SpendTransactions.transactData(spending: spent)
        let merge = SpendTransactions.mergeData(spending: spent)
        return [
            Array(transact.dropLast()),
            transact + [0],
            transact.replacingSubrange(58..<59, with: [1, 4]),
            transact.replacingSubrange(59..<60, with: [2]),
            transact.replacingSubrange(94..<95, with: [2]),
            transact.replacingSubrange(127..<128, with: [2]),
            transact.replacingSubrange(378..<379, with: [3]),
            transact.replacingSubrange(575..<576, with: [3]),
            Array(merge.dropLast()),
            merge + [0],
            merge.replacingSubrange(233..<234, with: [0]),
            merge.replacingSubrange(378..<379, with: [3]),
            merge.replacingSubrange(447..<448, with: [2]),
        ]
    }
}
