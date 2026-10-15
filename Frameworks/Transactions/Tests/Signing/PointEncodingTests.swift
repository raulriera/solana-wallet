import Foundation
import Testing
@testable import Transactions

/// Verifies small-order point recognition independently of signature verification.
struct PointEncodingTests {
    /// Verifies all fourteen published encodings, including sign and unreduced aliases.
    ///
    /// - Parameter hexadecimal: A small-order encoding from SIMD-0376.
    @Test(arguments: [
        "0000000000000000000000000000000000000000000000000000000000000000",
        "0000000000000000000000000000000000000000000000000000000000000080",
        "0100000000000000000000000000000000000000000000000000000000000000",
        "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05",
        "26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85",
        "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a",
        "c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa",
        "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
        "edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
        "edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f",
        "eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        "0100000000000000000000000000000000000000000000000000000000000080",
        "ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    ])
    func `Small-order points and their alternate encodings are recognized`(_ hexadecimal: String) throws {
        let bytes = try fixtureBytes(hexadecimal)

        #expect(PointEncoding.isSmallOrder(Data(bytes)))
    }
}
