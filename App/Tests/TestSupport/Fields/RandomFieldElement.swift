func randomFieldElement() -> [UInt8] {
    [0] + (0..<31).map { _ in UInt8.random(in: .min ... .max) }
}
