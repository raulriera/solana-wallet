import Testing

struct PrivateBalanceVectors: Decodable, Sendable {
    let accounts: [Account]

    let derivationInputGuard: [GuardVector]

    private enum CodingKeys: String, CodingKey {
        case accounts
        case derivationInputGuard = "derivation_input_guard"
    }

    struct Account: Decodable, Sendable, CustomTestStringConvertible {
        let account: UInt32
        let signingPubkey: String
        let nullifierSecret: String
        let viewingSecret: String
        let viewingPubkey: String

        var testDescription: String { "Account \(account)" }
    }

    struct GuardVector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let message: String
        let isDerivationInput: Bool

        private enum CodingKeys: String, CodingKey {
            case name, message
            case isDerivationInput = "is_derivation_input"
        }

        var testDescription: String { name }
    }

    static func load() throws -> Self {
        try fixture(named: "PrivateBalanceVectors")
    }

    static func guardVectors(named names: Set<String>) throws -> [GuardVector] {
        try load().derivationInputGuard.filter { names.contains($0.name) }
    }
}
