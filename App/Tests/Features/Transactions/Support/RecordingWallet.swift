import Foundation
import Wallet

actor RecordingWallet: MessageSigning {
    private(set) var messages: [Data] = []

    func signature(for message: Data, using phrase: RecoveryPhrase, expectedAddress: String,
                   passphrase: String, path: DerivationPath) async throws -> Data {
        messages.append(message)
        return try await Wallet().signature(for: message, using: phrase, expectedAddress: expectedAddress,
                                            passphrase: passphrase, path: path)
    }
}
