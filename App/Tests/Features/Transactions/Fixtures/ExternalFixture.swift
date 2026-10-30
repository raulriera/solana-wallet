import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

enum ExternalFixture {
    static let signer = "8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5"
    static let signature = "BR53jv5yHjwHJmwFUrRz5wLpzRaTvTEH2iGgMYHYBdJ3usUgwBFH4t1Hvq9erAzGF941uqVeTfesLXD3cNdL3tR"
    static let alternatePayerSignature = "WGZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmYtlO8YhBT8/YCdc4h8e8JkhNrH1DDlSyeJGXsa2BE9CA=="
    private static let complete = "gQIBAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAED8DYnYkanW53jNJ7UKxXiMvZRj8IPX81PHWToH5vSWPdq9CT8PAzHTh7H4ZgEoKie01G4PMsS3Q85uJSmpEljEgVKU1qZKSEGTSTocWDaOHx8NbXdvJK7geQfqEBBBUSNiBMAAAAAAAAgTgAAAAABAAICDgAAAVB1YmxpYyBmaXh0dXJlCPtDaapIEo5IhwWJZ+zz3CZTR3OGfyE5atS4lUaThhiJXOF5PxiV1T1gZo9kng2akzQPC/ZEJj3JlCL0IZPnBgetsaT+k+97/LXT3pjPViEN0S9WB+TZL/8MZRk4Cao9F5fug4Hegl897RAwjmcGIvITy3OqE03efy2+jSHaswE="

    static func signed(hasPayerSignature: Bool = true) throws -> Data {
        var bytes = try #require(Data(base64Encoded: complete))
        if !hasPayerSignature {
            bytes.replaceSubrange((bytes.count - 128)..<(bytes.count - 64), with: Data(repeating: 0, count: 64))
        }
        return bytes
    }

    static func unsigned(hasPayerSignature: Bool = true) throws -> Data {
        try signed(hasPayerSignature: hasPayerSignature).dropLast(64) + Data(repeating: 0, count: 64)
    }

    static func preparation(hasPayerSignature: Bool = true) throws -> Preparation {
        let observations = try PreparationFixture.preparation(fee: 15_000)
        return Preparation(source: .external(Context(slot: 400), lastValidBlockHeight: 650), signer: try Address(signer),
                           transaction: try TransactionDecoder().decode(unsigned(hasPayerSignature: hasPayerSignature)),
                           network: .devnet, fee: observations.fee, simulation: observations.simulation)
    }

    static func signedResult(hasPayerSignature: Bool = true) throws -> SignedTransaction {
        SignedTransaction(preparation: try preparation(hasPayerSignature: hasPayerSignature),
                          transaction: try TransactionDecoder().decode(signed(hasPayerSignature: hasPayerSignature)))
    }
}
