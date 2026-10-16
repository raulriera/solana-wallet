import ModularArithmetic
import Testing

/// Verifies field arithmetic against values derived by hand from each field's modulus.
///
/// Each parameterized test opens the fixture's field type with a local generic function.
struct FieldElementTests {
    /// Every field with the indices i and j of each ordered pair of its edge values.
    ///
    /// The edge values are 0, 1, 2, m - 1, m - 2, (m + 1) / 2, 2^64 - 1, 2^64, 2^128 - 1, 2^128,
    /// 2^192 - 1, 2^192, and the values with all-ones limbs or 2^255 that are below m.
    private static let edgeValueIndexPairs: [(FieldFixture, Int, Int)] = FieldFixture.all.flatMap { fixture in
        fixture.edgeValues.indices.flatMap { i in fixture.edgeValues.indices.map { j in (fixture, i, j) } }
    }

    /// Verifies that canonical values survive conversion into and out of Montgomery form.
    ///
    /// The values are 0, 1, 2^64 - 1, m - 1, and (m + 1) / 2, each derived as documented on
    /// ``FieldFixture``.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - hex: A canonical value in that field.
    @Test(arguments: FieldFixture.all.flatMap { fixture in
        [FieldFixture.zero, FieldFixture.one, FieldFixture.maximumLimb, fixture.modulusMinusOne, fixture.half].map { (fixture, $0) }
    })
    func `Canonical bytes round-trip through Montgomery form`(_ fixture: FieldFixture, hex: String) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let bytes = try fixtureBytes(hex)
            #expect(FieldElement<Field>(bigEndianBytes: bytes)?.bigEndianBytes == bytes)
        }
        try check(fixture.field)
    }

    /// Verifies that integers and the identities encode as their own big-endian bytes.
    ///
    /// Every integer below 2^64 is below the modulus, so its canonical encoding is the integer
    /// itself, left-padded with zero bytes.
    ///
    /// - Parameter fixture: A field and values derived from its modulus.
    @Test(arguments: FieldFixture.all)
    func `Integers and identities encode as their canonical bytes`(_ fixture: FieldFixture) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let zero = try fixtureBytes(FieldFixture.zero)
            let one = try fixtureBytes(FieldFixture.one)

            #expect(FieldElement<Field>(0).bigEndianBytes == zero)
            #expect(FieldElement<Field>(1).bigEndianBytes == one)
            #expect(FieldElement<Field>(.max).bigEndianBytes == (try fixtureBytes(FieldFixture.maximumLimb)))
            #expect(FieldElement<Field>.zero.bigEndianBytes == zero)
            #expect(FieldElement<Field>.one.bigEndianBytes == one)
        }
        try check(fixture.field)
    }

    /// Verifies that canonical decoding rejects other lengths and values at or above the modulus.
    ///
    /// m comes from the field's specification; 2^256 - 1 is the largest 32-byte value.
    ///
    /// - Parameter fixture: A field and values derived from its modulus.
    @Test(arguments: FieldFixture.all)
    func `Canonical decoding rejects other lengths and values at or above the modulus`(_ fixture: FieldFixture) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            #expect(FieldElement<Field>(bigEndianBytes: [UInt8](repeating: 0, count: 31)) == nil)
            #expect(FieldElement<Field>(bigEndianBytes: [UInt8](repeating: 0, count: 33)) == nil)
            #expect(FieldElement<Field>(bigEndianBytes: try fixtureBytes(fixture.modulus)) == nil)
            #expect(FieldElement<Field>(bigEndianBytes: try fixtureBytes(FieldFixture.maximum)) == nil)
        }
        try check(fixture.field)
    }

    /// Verifies that reduction leaves each value's remainder modulo m.
    ///
    /// m and m + 1 leave 0 and 1. A known multiple of m plus a remainder leaves that remainder:
    /// 5r + 7 for BN254, 5p + 7 for its base field, and n + 2^64 - 1 for P-256. 2^256 - 1 leaves the complement of the
    /// largest multiple of m below 2^256. A canonical value, m - 1, is unchanged.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - reduction: A 32-byte value and its remainder modulo the field's modulus.
    @Test(arguments: FieldFixture.all.flatMap { fixture in
        [
            FieldFixture.Reduction(value: fixture.modulus, remainder: FieldFixture.zero),
            FieldFixture.Reduction(value: fixture.modulusPlusOne, remainder: FieldFixture.one),
            fixture.multiple,
            FieldFixture.Reduction(value: FieldFixture.maximum, remainder: fixture.maximumRemainder),
            FieldFixture.Reduction(value: fixture.modulusMinusOne, remainder: fixture.modulusMinusOne),
        ].map { (fixture, $0) }
    })
    func `Reduction leaves the remainder modulo the modulus`(_ fixture: FieldFixture, reduction: FieldFixture.Reduction) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let reduced = FieldElement<Field>(reducing: try fixtureBytes(reduction.value))
            #expect(reduced.bigEndianBytes == (try fixtureBytes(reduction.remainder)))
        }
        try check(fixture.field)
    }

    /// Verifies that addition, subtraction, and negation wrap at the modulus.
    ///
    /// (m - 1) + 1 = m ≡ 0, 0 - 1 ≡ m - 1, -0 = 0, and (m - 1) + (m - 1) = 2m - 2 ≡ m - 2, which
    /// carries above 2^256 for P-256.
    ///
    /// - Parameter fixture: A field and values derived from its modulus.
    @Test(arguments: FieldFixture.all)
    func `Addition, subtraction, and negation wrap at the modulus`(_ fixture: FieldFixture) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let minusOne = try FieldElement<Field>(hex: fixture.modulusMinusOne)
            let zero = try fixtureBytes(FieldFixture.zero)

            #expect((minusOne + .one).bigEndianBytes == zero)
            #expect((FieldElement<Field>.zero - .one).bigEndianBytes == (try fixtureBytes(fixture.modulusMinusOne)))
            #expect((-FieldElement<Field>.zero).bigEndianBytes == zero)
            #expect((minusOne + minusOne).bigEndianBytes == (try fixtureBytes(fixture.modulusMinusTwo)))
        }
        try check(fixture.field)
    }

    /// Verifies that an edge value plus its negation is zero.
    ///
    /// The edge values lie at limb boundaries and near the modulus, as ``FieldFixture/edgeValues``
    /// lists them.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - hex: An edge value in that field.
    @Test(arguments: FieldFixture.all.flatMap { fixture in fixture.edgeValues.map { (fixture, $0) } })
    func `Every edge value plus its negation is zero`(_ fixture: FieldFixture, hex: String) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let value = try FieldElement<Field>(hex: hex)
            #expect((value + -value).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
        }
        try check(fixture.field)
    }

    /// Verifies that products of integers below 2^64 match their integer products.
    ///
    /// These products are below 2^128, which is below every modulus, so no reduction applies; the
    /// expected bytes come from 128-bit integer multiplication.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - factors: Two integers below 2^64.
    @Test(arguments: FieldFixture.all, [
        (0, .max), (1, .max), (2, 3), (7, 11),
        (0xffff_ffff, 0x1_0000_0001), (0x1_0000_0000, 0x1_0000_0000),
        (0xdead_beef_cafe_f00d, 0x0123_4567_89ab_cdef), (.max, .max),
    ] as [(UInt64, UInt64)])
    func `Products of small integers match integer products`(_ fixture: FieldFixture, factors: (UInt64, UInt64)) {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) {
            let expected = FieldFixture.bytes(of: UInt128(factors.0) * UInt128(factors.1))
            #expect((FieldElement<Field>(factors.0) * FieldElement<Field>(factors.1)).bigEndianBytes == expected)
        }
        check(fixture.field)
    }

    /// Verifies that equality matches the canonical bytes for a pair of edge values.
    ///
    /// The edge values are distinct, so two of them are equal exactly when they share an index.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - i: The index of the left-hand edge value.
    ///   - j: The index of the right-hand edge value.
    @Test(arguments: edgeValueIndexPairs)
    func `Equality matches canonical bytes`(_ fixture: FieldFixture, i: Int, j: Int) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let lhs = try FieldElement<Field>(hex: fixture.edgeValues[i])
            let rhs = try FieldElement<Field>(hex: fixture.edgeValues[j])
            #expect((lhs == rhs) == (i == j))
        }
        try check(fixture.field)
    }

    /// Verifies that reducing m + 1 gives an element equal to ``FieldElement/one``.
    ///
    /// m + 1 ≡ 1, so the reduced element equals ``FieldElement/one``, which is built from R mod m
    /// instead.
    ///
    /// - Parameter fixture: A field and values derived from its modulus.
    @Test(arguments: FieldFixture.all)
    func `Reducing the modulus plus one equals one`(_ fixture: FieldFixture) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            #expect(FieldElement<Field>(reducing: try fixtureBytes(fixture.modulusPlusOne)) == .one)
        }
        try check(fixture.field)
    }

    /// Verifies that equality compares one limb of the stored Montgomery form.
    ///
    /// Elements are stored as their value times R = 2^256. R mod m is (2^256 - 1 mod m) + 1, so
    /// 2^(64k) / R is stored as exactly 2^(64k), which differs from zero in limb k alone.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - boundary: 2^(64k), the lowest bit of limb k.
    @Test(arguments: FieldFixture.all, FieldFixture.limbBoundaries)
    func `Equality compares every stored limb`(_ fixture: FieldFixture, boundary: String) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let factor = FieldElement<Field>(reducing: try fixtureBytes(FieldFixture.maximum)) + .one
            let limb = try FieldElement<Field>(hex: boundary) * factor.inverse()
            #expect(limb != .zero)
        }
        try check(fixture.field)
    }

    /// Verifies that addition and multiplication commute, and that subtraction undoes addition, for
    /// a pair of edge values.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - i: The index of the edge value a.
    ///   - j: The index of the edge value b.
    @Test(arguments: edgeValueIndexPairs)
    func `Addition and multiplication commute and subtraction undoes addition on edge values`(
        _ fixture: FieldFixture, i: Int, j: Int
    ) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let a = try FieldElement<Field>(hex: fixture.edgeValues[i])
            let b = try FieldElement<Field>(hex: fixture.edgeValues[j])

            #expect(a + b == b + a)
            #expect(a * b == b * a)
            #expect((a - b) + b == a)
        }
        try check(fixture.field)
    }

    /// Verifies that addition and multiplication associate, and that multiplication distributes over
    /// addition, for a pair of edge values with every edge value as the third.
    ///
    /// Each law collects the indices k of the third values c that break it, so a failure lists them.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - i: The index of the edge value a.
    ///   - j: The index of the edge value b.
    @Test(arguments: edgeValueIndexPairs)
    func `Addition and multiplication associate and distribute on edge values`(
        _ fixture: FieldFixture, i: Int, j: Int
    ) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let values = try fixture.edgeValues.map { try FieldElement<Field>(hex: $0) }
            let a = values[i]
            let b = values[j]

            let nonAssociativeSums = values.indices.filter { k in (a + b) + values[k] != a + (b + values[k]) }
            let nonAssociativeProducts = values.indices.filter { k in (a * b) * values[k] != a * (b * values[k]) }
            let nonDistributiveProducts = values.indices.filter { k in a * (b + values[k]) != a * b + a * values[k] }

            #expect(nonAssociativeSums.isEmpty)
            #expect(nonAssociativeProducts.isEmpty)
            #expect(nonDistributiveProducts.isEmpty)
        }
        try check(fixture.field)
    }

    /// Verifies that a value times its inverse is one.
    ///
    /// The values are 1, 2, 7, and m - 1.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - hex: A nonzero value in that field.
    @Test(arguments: FieldFixture.all.flatMap { fixture in
        [
            FieldFixture.one,
            FieldFixture.two,
            "0000000000000000000000000000000000000000000000000000000000000007",
            fixture.modulusMinusOne,
        ].map { (fixture, $0) }
    })
    func `Inverses multiply to one`(_ fixture: FieldFixture, hex: String) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let value = try FieldElement<Field>(hex: hex)
            #expect((value * value.inverse()).bigEndianBytes == (try fixtureBytes(FieldFixture.one)))
        }
        try check(fixture.field)
    }

    /// Verifies the inverses that follow from the modulus.
    ///
    /// 1⁻¹ = 1, 2⁻¹ = (m + 1) / 2 because 2 × (m + 1) / 2 = m + 1 ≡ 1, and (m - 1)⁻¹ = m - 1
    /// because (-1) × (-1) = 1.
    ///
    /// - Parameters:
    ///   - fixture: A field and values derived from its modulus.
    ///   - hex: A nonzero value in that field.
    ///   - inverseHex: The value's inverse.
    @Test(arguments: FieldFixture.all.flatMap { fixture in
        [
            (FieldFixture.one, FieldFixture.one),
            (FieldFixture.two, fixture.half),
            (fixture.modulusMinusOne, fixture.modulusMinusOne),
        ].map { (fixture, $0.0, $0.1) }
    })
    func `Known inverses follow from the modulus`(_ fixture: FieldFixture, hex: String, inverseHex: String) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            let value = try FieldElement<Field>(hex: hex)
            #expect(value.inverse().bigEndianBytes == (try fixtureBytes(inverseHex)))
        }
        try check(fixture.field)
    }

    /// Verifies the documented inverse of zero: zero raised to m - 2 is zero.
    ///
    /// - Parameter fixture: A field and values derived from its modulus.
    @Test(arguments: FieldFixture.all)
    func `The inverse of zero is zero`(_ fixture: FieldFixture) throws {
        /// Checks the field that `fixture` describes.
        func check<Field: PrimeField>(_: Field.Type) throws {
            #expect(FieldElement<Field>.zero.inverse().bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
        }
        try check(fixture.field)
    }

    /// Verifies that ordinary descriptions and reflection don't reveal the value.
    @Test
    func `Field element descriptions omit the value`() {
        let element = FieldElement<BN254ScalarField>(7)

        #expect(String(describing: element) == "FieldElement")
        #expect(String(reflecting: element) == "FieldElement")
        #expect(Mirror(reflecting: element).children.isEmpty)
    }
}
