import Foundation
import RPC
import Testing
import Transactions
@testable import widgets

/// An independently signed Kit 8.0.0 envelope with a payer and a read-only cosigner.
///
/// Both keys derive from the public BIP-39 zero-entropy phrase. The cosigner uses
/// TREZOR and m/44'/501'/1'/0'; its recovery is shared with SigningFixture.
enum ExternalFixture {
    static let signer = "8CW93AFYFKj2rKZRq3YjLesb4XbgtAiq8k2FgfruVZL5"
    /// The independent Kit Base58 encoding of the fixture's fee-payer signature.
    static let signature = "BR53jv5yHjwHJmwFUrRz5wLpzRaTvTEH2iGgMYHYBdJ3usUgwBFH4t1Hvq9erAzGF941uqVeTfesLXD3cNdL3tR"
    /// A second valid payer signature, generated offline with r = 1 and verified by Kit.
    static let alternatePayerSignature = "WGZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmZmYtlO8YhBT8/YCdc4h8e8JkhNrH1DDlSyeJGXsa2BE9CA=="
    private static let complete = "gQIBAQ8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAED8DYnYkanW53jNJ7UKxXiMvZRj8IPX81PHWToH5vSWPdq9CT8PAzHTh7H4ZgEoKie01G4PMsS3Q85uJSmpEljEgVKU1qZKSEGTSTocWDaOHx8NbXdvJK7geQfqEBBBUSNiBMAAAAAAAAgTgAAAAABAAICDgAAAVB1YmxpYyBmaXh0dXJlCPtDaapIEo5IhwWJZ+zz3CZTR3OGfyE5atS4lUaThhiJXOF5PxiV1T1gZo9kng2akzQPC/ZEJj3JlCL0IZPnBgetsaT+k+97/LXT3pjPViEN0S9WB+TZL/8MZRk4Cao9F5fug4Hegl897RAwjmcGIvITy3OqE03efy2+jSHaswE="

    /// Returns the independently signed wire fixture, optionally removing the payer's signature.
    ///
    /// - Parameter hasPayerSignature: Whether to retain the independent payer signature.
    /// - Returns: A complete V1 envelope with the wallet cosigner's expected signature.
    /// - Throws: A test failure if the Base64 fixture is malformed.
    static func signed(hasPayerSignature: Bool = true) throws -> Data {
        var bytes = try #require(Data(base64Encoded: complete))
        if !hasPayerSignature {
            bytes.replaceSubrange((bytes.count - 128)..<(bytes.count - 64), with: Data(repeating: 0, count: 64))
        }
        return bytes
    }

    /// Removes only the selected wallet's signature from the independent SDK fixture.
    ///
    /// - Parameter hasPayerSignature: Whether the input is partially signed or fully unsigned.
    /// - Returns: The envelope to prepare and sign through the app coordinator.
    /// - Throws: A test fixture decoding error.
    static func unsigned(hasPayerSignature: Bool = true) throws -> Data {
        try signed(hasPayerSignature: hasPayerSignature).dropLast(64) + Data(repeating: 0, count: 64)
    }

    /// Creates external review observations without performing network or wallet access.
    ///
    /// - Parameter hasPayerSignature: Whether the independent payer signature is present.
    /// - Returns: Typed observations encoded by the HTTP fixtures.
    /// - Throws: A fixture or structural decoding error.
    static func preparation(hasPayerSignature: Bool = true) throws -> Preparation {
        let observations = try PreparationFixture.preparation(fee: 15_000)
        return Preparation(source: .external(Context(slot: 400)), signer: try Address(signer),
                           transaction: try TransactionDecoder().decode(unsigned(hasPayerSignature: hasPayerSignature)),
                           network: .devnet, fee: observations.fee, simulation: observations.simulation)
    }

    /// Wraps the independently signed fixture in its original review for submission checks.
    ///
    /// - Parameter hasPayerSignature: Whether every required signer is present.
    /// - Returns: A typed result without accessing wallet recovery or networking.
    /// - Throws: A fixture decoding error.
    static func signedResult(hasPayerSignature: Bool = true) throws -> SignedTransaction {
        SignedTransaction(preparation: try preparation(hasPayerSignature: hasPayerSignature),
                          transaction: try TransactionDecoder().decode(signed(hasPayerSignature: hasPayerSignature)))
    }
}
