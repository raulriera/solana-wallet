import CryptoKit
import Encoding

extension Wallet {
    @concurrent
    public func accounts(for phrase: RecoveryPhrase, passphrase: String,
                         paths: [DerivationPath]) async throws -> [DerivedAccount] {
        try Task.checkCancellation()
        guard !paths.isEmpty else { return [] }
        var seed = try SeedDerivation.seed(for: phrase, passphrase: passphrase)
        defer { seed.erase() }
        let accounts = try paths.map { path in
            let key = try KeyDerivation.signingKey(seed: seed, path: path)
            return DerivedAccount(address: Base58.encode(Array(key.publicKey.rawRepresentation)), path: path)
        }
        try Task.checkCancellation()
        return accounts
    }
}
