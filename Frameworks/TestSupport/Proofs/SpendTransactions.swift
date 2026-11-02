import Encoding
import Foundation
import RPC
@testable import Privacy

nonisolated enum SpendTransactions {
    typealias Call = (program: String, data: [UInt8])

    static let program = "ring1GaLCuJnkUMVkX2JeZLTTX17wKsV4fZmPVzXANW"

    static let payer = "GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB"

    static let failure = #"{"InstructionError":[0,{"Custom":6001}]}"#

    static func transactData(
        spending nullifiers: [[UInt8]],
        tag: UInt8 = 16,
        circuit: UInt16 = 0,
        withdrawing lamports: UInt64? = nil,
        includesOptionalFields: Bool = false
    ) -> [UInt8] {
        var transfers: [[UInt8]] = lamports.map { [amount(1, $0)] } ?? []
        var outputs: [[UInt8]] = [
            [UInt8](repeating: 11, count: 32) + [0] + [UInt8](repeating: 12, count: 32) + [1, 89, 0] + [UInt8](repeating: 13, count: 89),
            [UInt8](repeating: 14, count: 32) + [1, 0] + [1, 89, 0] + [UInt8](repeating: 15, count: 89),
        ]
        var hashes: [UInt8] = [0, 0]
        var messages: [[UInt8]] = []
        if includesOptionalFields {
            transfers += [amount(0, 5), amount(2, 6) + [254], amount(3, 7) + [253]]
            hashes = [1] + [UInt8](repeating: 0x31, count: 32) + [1] + [UInt8](repeating: 0x32, count: 32)
            outputs.append([UInt8](repeating: 0x33, count: 32) + [0] + [UInt8](repeating: 0x34, count: 32) + [0])
            messages.append([UInt8](repeating: 0x41, count: 32) + [4, 0] + [UInt8](repeating: 0x42, count: 4))
        }
        var data: [UInt8] = [tag] + [UInt8](repeating: 0xff, count: 8) + [3] + [UInt8](repeating: 7, count: 32)
            + [UInt8](repeating: 5, count: 16)
        data += [UInt8(transfers.count)] + transfers.joined() + hashes
        data += [UInt8(outputs.count)] + outputs.joined() + [UInt8(messages.count)] + messages.joined()
        data += [UInt8](repeating: 16, count: 32)
        data.appendLittleEndian(circuit)
        data += [UInt8(nullifiers.count), 2, 3]
        if [7, 8].contains(circuit) { data += [UInt8](repeating: 0x51, count: 96) }
        if [4, 5, 8].contains(circuit) {
            data.appendLittleEndian(UInt64(1))
            data += [0, 0] + [UInt8](repeating: 0xff, count: 30)
        }
        data += [UInt8](repeating: 17, count: 192)
        data += [UInt8(nullifiers.count)] + nullifiers.flatMap { $0 + [0] } + [1, 8, 0, 0, 0]
        return data
    }

    static func mergeData(spending nullifiers: [[UInt8]], tag: UInt8 = 17, cacheSlot: UInt8? = nil) -> [UInt8] {
        [tag] + [UInt8](repeating: 0xff, count: 8) + [UInt8](repeating: 17, count: 192) + [UInt8](repeating: 11, count: 32)
            + [1] + [UInt8](repeating: 5, count: 16) + [UInt8](repeating: 13, count: 96) + [UInt8](repeating: 16, count: 32)
            + [UInt8(nullifiers.count)] + nullifiers.joined() + [8, 0, 0, 0] + (cacheSlot.map { [1, $0] } ?? [0])
    }

    static func result(spending nullifiers: [[UInt8]], error: String = "null") -> String {
        result(of: [(program, transactData(spending: nullifiers))], error: error)
    }

    static func result(of instructions: [Call], inner: [Call] = [], error: String = "null") -> String {
        var keys = [payer]
        for call in instructions + inner where !keys.contains(call.program) { keys.append(call.program) }
        let compiled = { (calls: [Call]) in
            calls.map { call in
                #"{"programIdIndex":\#(keys.firstIndex(of: call.program) ?? 0),"accounts":[0],"#
                    + #""data":"\#(Base58.encode(call.data))","stackHeight":1}"#
            }.joined(separator: ",")
        }
        let accountKeys = keys.map { "\"\($0)\"" }.joined(separator: ",")
        let invoked = inner.isEmpty ? "[]" : #"[{"index":0,"instructions":[\#(compiled(inner))]}]"#
        return #"{"slot":20,"blockTime":1,"version":1,"meta":{"err":\#(error),"fee":5000,"innerInstructions":\#(invoked),"#
            + #""loadedAddresses":{"writable":[],"readonly":[]},"logMessages":[],"preBalances":[],"postBalances":[]},"#
            + #""transaction":{"signatures":[],"message":{"accountKeys":[\#(accountKeys)],"#
            + #""header":{"numRequiredSignatures":1,"numReadonlySignedAccounts":0,"numReadonlyUnsignedAccounts":1},"#
            + #""recentBlockhash":"11111111111111111111111111111111","instructions":[\#(compiled(instructions))]}}}"#
    }

    static func transaction(of instructions: [Call], inner: [Call] = [], error: String = "null") throws -> GetTransaction.Value {
        try JSONDecoder().decode(GetTransaction.Value.self, from: Data(result(of: instructions, inner: inner, error: error).utf8))
    }

    private static func amount(_ kind: UInt8, _ lamports: UInt64) -> [UInt8] {
        var bytes = [kind]
        bytes.appendLittleEndian(lamports)
        return bytes
    }
}
