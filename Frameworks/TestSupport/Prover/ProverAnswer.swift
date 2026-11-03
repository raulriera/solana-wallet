import Encoding
import Testing

enum ProverAnswer {
    static let treeAddress = "33KVhbT4QtdQDrrrGwwThqD47Dh4Q6tA443t9jMNcWFN"

    static let zeroAddress = String(repeating: "1", count: 32)

    static func word(_ bytes: [UInt8]) -> JSONValue {
        .string("0x" + Hex.encode(bytes))
    }

    static func word(_ value: UInt8) -> JSONValue {
        word(fieldElement(value))
    }

    static func proof(a: JSONValue = [word(1), word(2)], b: JSONValue = [[word(3), word(4)], [word(5), word(6)]],
                      c: JSONValue = [word(7), word(8)],
                      digest: JSONValue? = .string(String(repeating: "7e", count: 32))) -> JSONValue {
        var members: [String: JSONValue] = ["ar": a, "bs": b, "krs": c]
        members["provingKeySha256"] = digest
        return .object(members)
    }

    static func tree(tree: JSONValue = .string(treeAddress), id: JSONValue = 0, utxoRoot: JSONValue = word(0x71),
                     nullifierRoot: JSONValue = word(0x72), utxoRootIndex: JSONValue = 7,
                     nullifierRootIndex: JSONValue = 8) -> JSONValue {
        [
            "tree": tree, "id": id, "utxoRoot": utxoRoot, "nullifierRoot": nullifierRoot,
            "utxoRootIndex": utxoRootIndex, "nullifierRootIndex": nullifierRootIndex,
        ]
    }

    static func indexed(proof: JSONValue = proof(), trees: JSONValue? = [tree()],
                        publicInputHash: JSONValue? = word(0x99)) throws -> JSONValue {
        var members = try #require(proof.members)
        var resolution: [String: JSONValue] = [:]
        resolution["trees"] = trees
        resolution["publicInputHash"] = publicInputHash
        members["resolution"] = .object(resolution)
        return .object(members)
    }
}
