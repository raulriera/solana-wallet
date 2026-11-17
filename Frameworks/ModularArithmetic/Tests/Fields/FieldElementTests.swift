import ModularArithmetic
import Testing

struct FieldElementTests {
    private static let edgeValueIndexPairs: [(FieldFixture, Int, Int)] = FieldFixture.all.flatMap { fixture in
        fixture.edgeValues.indices.flatMap { i in fixture.edgeValues.indices.map { j in (fixture, i, j) } }
    }

    @Test(arguments: FieldFixture.all.flatMap { fixture in
        [FieldFixture.zero, FieldFixture.one, FieldFixture.maximumLimb, fixture.modulusMinusOne, fixture.half].map { (fixture, $0) }
    })
    func `Canonical bytes round-trip through Montgomery form`(_ fixture: FieldFixture, hex: String) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            let bytes = try fixtureBytes(hex)
            #expect(FieldElement<Field>(bigEndianBytes: bytes)?.bigEndianBytes == bytes)
        }
        try check(fixture.field)
    }

    @Test(arguments: FieldFixture.all)
    func `Integers and identities encode as their canonical bytes`(_ fixture: FieldFixture) throws {
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

    @Test(arguments: FieldFixture.all)
    func `Canonical decoding rejects other lengths and values at or above the modulus`(_ fixture: FieldFixture) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            #expect(FieldElement<Field>(bigEndianBytes: [UInt8](repeating: 0, count: 31)) == nil)
            #expect(FieldElement<Field>(bigEndianBytes: [UInt8](repeating: 0, count: 33)) == nil)
            #expect(FieldElement<Field>(bigEndianBytes: try fixtureBytes(fixture.modulus)) == nil)
            #expect(FieldElement<Field>(bigEndianBytes: try fixtureBytes(FieldFixture.maximum)) == nil)
        }
        try check(fixture.field)
    }

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
        func check<Field: PrimeField>(_: Field.Type) throws {
            let reduced = FieldElement<Field>(reducing: try fixtureBytes(reduction.value))
            #expect(reduced.bigEndianBytes == (try fixtureBytes(reduction.remainder)))
        }
        try check(fixture.field)
    }

    @Test(arguments: FieldFixture.all.flatMap { fixture in fixture.edgeValues.map { (fixture, $0) } })
    func `Every edge value plus its negation is zero`(_ fixture: FieldFixture, hex: String) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            let value = try FieldElement<Field>(hex: hex)
            #expect((value + -value).bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
        }
        try check(fixture.field)
    }

    @Test(arguments: FieldFixture.all, [
        (0, .max), (1, .max), (2, 3), (7, 11),
        (0xffff_ffff, 0x1_0000_0001), (0x1_0000_0000, 0x1_0000_0000),
        (0xdead_beef_cafe_f00d, 0x0123_4567_89ab_cdef), (.max, .max),
    ] as [(UInt64, UInt64)])
    func `Products of small integers match integer products`(_ fixture: FieldFixture, factors: (UInt64, UInt64)) {
        func check<Field: PrimeField>(_: Field.Type) {
            let expected = FieldFixture.bytes(of: UInt128(factors.0) * UInt128(factors.1))
            #expect((FieldElement<Field>(factors.0) * FieldElement<Field>(factors.1)).bigEndianBytes == expected)
        }
        check(fixture.field)
    }

    @Test(arguments: edgeValueIndexPairs)
    func `Equality matches canonical bytes`(_ fixture: FieldFixture, i: Int, j: Int) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            let lhs = try FieldElement<Field>(hex: fixture.edgeValues[i])
            let rhs = try FieldElement<Field>(hex: fixture.edgeValues[j])
            #expect((lhs == rhs) == (i == j))
        }
        try check(fixture.field)
    }

    @Test(arguments: edgeValueIndexPairs)
    func `Addition and multiplication commute, associate, distribute, and cancel on edge values`(
        _ fixture: FieldFixture, i: Int, j: Int
    ) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            let values = try fixture.edgeValues.map { try FieldElement<Field>(hex: $0) }
            let a = values[i]
            let b = values[j]

            #expect(a + b == b + a)
            #expect(a * b == b * a)
            #expect((a - b) + b == a)

            let nonAssociativeSums = values.indices.filter { k in (a + b) + values[k] != a + (b + values[k]) }
            let nonAssociativeProducts = values.indices.filter { k in (a * b) * values[k] != a * (b * values[k]) }
            let nonDistributiveProducts = values.indices.filter { k in a * (b + values[k]) != a * b + a * values[k] }

            #expect(nonAssociativeSums.isEmpty)
            #expect(nonAssociativeProducts.isEmpty)
            #expect(nonDistributiveProducts.isEmpty)
        }
        try check(fixture.field)
    }

    @Test(arguments: FieldFixture.all.flatMap { fixture in
        [
            FieldFixture.one,
            FieldFixture.two,
            "0000000000000000000000000000000000000000000000000000000000000007",
            fixture.modulusMinusOne,
        ].map { (fixture, $0) }
    })
    func `Inverses multiply to one`(_ fixture: FieldFixture, hex: String) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            let value = try FieldElement<Field>(hex: hex)
            #expect((value * value.inverse()).bigEndianBytes == (try fixtureBytes(FieldFixture.one)))
        }
        try check(fixture.field)
    }

    @Test(arguments: FieldFixture.all.flatMap { fixture in
        [
            (FieldFixture.one, FieldFixture.one),
            (FieldFixture.two, fixture.half),
            (fixture.modulusMinusOne, fixture.modulusMinusOne),
        ].map { (fixture, $0.0, $0.1) }
    })
    func `Known inverses follow from the modulus`(_ fixture: FieldFixture, hex: String, inverseHex: String) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            let value = try FieldElement<Field>(hex: hex)
            #expect(value.inverse().bigEndianBytes == (try fixtureBytes(inverseHex)))
        }
        try check(fixture.field)
    }

    @Test(arguments: FieldFixture.all)
    func `The inverse of zero is zero`(_ fixture: FieldFixture) throws {
        func check<Field: PrimeField>(_: Field.Type) throws {
            #expect(FieldElement<Field>.zero.inverse().bigEndianBytes == (try fixtureBytes(FieldFixture.zero)))
        }
        try check(fixture.field)
    }
}
