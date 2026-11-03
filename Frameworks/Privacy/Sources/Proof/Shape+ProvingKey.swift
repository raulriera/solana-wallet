import Encoding

extension Shape {
    /// The SHA-256 digest of the shape's proving key.
    var provingKeyDigest: [UInt8] {
        guard let hex = Self.hexadecimalDigests[self], let digest = Hex.decode(hex) else {
            preconditionFailure("Every supported shape has a hexadecimal proving key digest.")
        }
        return digest
    }

    private static let hexadecimalDigests: [Shape: String] = [
        Shape(inputs: 1, outputs: 2): "c0b5c1a1081136911a6ad5496fb989ed26d85b09e983a4d5048cff96e0833d85",
        Shape(inputs: 1, outputs: 4): "4dea477eb3accc708975c4f258a9a58b8d5e21d2cc0dfa28ad47ba46b0fe7bff",
        Shape(inputs: 1, outputs: 8): "8bbdb200e1d6147ad03ef55e13e8271eca2973bf2ae59fe2f10f9e21b1def490",
        Shape(inputs: 2, outputs: 2): "51380b1264737ebd4d31f40ebf6874db039078ce998d4fa187c049ace99798bb",
        Shape(inputs: 2, outputs: 4): "835d0d4c5ff4d4be96902faa4cb2fe2ee2e413afe678729e853351e6c31c156b",
        Shape(inputs: 1, outputs: 16): "17c0f2a1d4494a3db56b332b2adc6a989a798c59f4683b649c4dac412bc82e26",
        Shape(inputs: 2, outputs: 8): "0b38f1f375024c6109c6b9027da8778c1140fc499ae45f52d5997f3d7e3f7529",
        Shape(inputs: 3, outputs: 2): "72379691c3b515ff939a9e57fa52204489bdae376642a4e675c0b8830118b097",
        Shape(inputs: 3, outputs: 4): "e6ed1362e59289b59bc11b93c85df9ebfbe7dfc8ba5f99a254273320ca07e7c9",
        Shape(inputs: 2, outputs: 16): "cebe6bb76188f3989dc011f7839f04867a8e8d448b6faa2a15a5f5f6e6a23901",
        Shape(inputs: 3, outputs: 8): "c41930ae5c21f8c582eb6c0c597e13b3bb249efcb85a756e4289cbb5c70e5a0b",
        Shape(inputs: 4, outputs: 2): "d9298a68c83261700a4d3eab6a1922aab19e625a843d9df50628c3ec86e43aee",
        Shape(inputs: 4, outputs: 4): "99e9a089100e820d8b539e45e24e48d61b113a43ea0e86ecbe979167b92d6a2b",
        Shape(inputs: 4, outputs: 8): "900598583206f654dd29cbe26d973cd258775b9c9c7413d061fa0616c1dbb3e3",
        Shape(inputs: 5, outputs: 2): "c5dfa2067fec93936aef24b748378516c40ef0a4f6987118e36285893864d45a",
        Shape(inputs: 5, outputs: 4): "9cb1497158d00e87dec62de29886f5d91fd0359ce15e77a9b3e0e26008e724cb",
        Shape(inputs: 4, outputs: 16): "8fbd730435bc5a5467b2184254f7080a7f75e135c5bcc5c633d76b0744e75bb4",
        Shape(inputs: 5, outputs: 8): "54e80daa5cfda22be5f1e82541fa0b798c83ccd34591e3b8b90104c8cb372577",
        Shape(inputs: 6, outputs: 2): "226387d770058209d40029988d6f3ab154c42a0802ee066284db4c8db886ca40",
        Shape(inputs: 6, outputs: 4): "c5ada6e9644e4853fc91a56cef7318fec9026c08475b8794a0e8026c80310171",
        Shape(inputs: 5, outputs: 16): "086961ca937381318413976c4e9b508541d2ab2bc758e1b28d9d9a99d66f27a4",
        Shape(inputs: 6, outputs: 8): "801717d5356cc171cb2b560562c292b21ccdef00c8e7deda6e827235d4cd8a6d",
        Shape(inputs: 8, outputs: 2): "b64dcce8e5a55ae0f120bd32118f5bfdaf88f48bb3a3860e9cae9bac1611135e",
        Shape(inputs: 8, outputs: 4): "74638c0bdf583defcf094fb7188e1fec98bedc2451680a850495e8015bb4384b",
        Shape(inputs: 8, outputs: 8): "501577f4062fe597a80ed22831c5b0e65e0a7a524283ce5e2f98c5868f7e8296",
        Shape(inputs: 8, outputs: 16): "88a98eee4be2853492e70dbbfb17a1e80bdedbe4d33b5cea9fe9ece97c945d19",
        Shape(inputs: 12, outputs: 2): "663d0de50bc0e6947492cad785ea5d34db51bfddeb59a5ed22d4722cf16a9190",
        Shape(inputs: 12, outputs: 4): "cecc67b4395dd1476d6a1c9d59d42c43b3f22ddb93f329892d4e8f8ebcebc7ed",
        Shape(inputs: 12, outputs: 8): "6637d73f12bb2255019a487910e9804bab103b4324e108bc520dd6c0b6ba09fc",
        Shape(inputs: 16, outputs: 2): "11951e7ef3f79f163a2c8aa9555651d9fba23424150da4701b7cc56f5b45d83f",
        Shape(inputs: 16, outputs: 4): "841988d4b2fc5f7366b7b823ec8abb58bf0b051b30319040935a5597f1681bce",
        Shape(inputs: 16, outputs: 8): "f8420af31bfb34ea029c5646769065ffc261c499b517f868542af0e0577c2676",
        Shape(inputs: 24, outputs: 2): "07d52d5f44e69013a47da95507c99dc2c4d0d1a3b16cd5d988bdacce069f6332",
        Shape(inputs: 24, outputs: 4): "694d6414fcc0392512eb7e071a3b28f30c8bb82adcb56962ccbf79807dc22c83",
        Shape(inputs: 32, outputs: 2): "7cb3a9c9662eee23effcfa495e0346fc30f383968ec1f3b7f330926f753dcd44",
        Shape(inputs: 40, outputs: 2): "1c307ca4ff52000e4e85f06e93437de826a2796b77233d5728d84216fdf6b2d4",
        Shape(inputs: 48, outputs: 2): "f429ba983f78510004cdbba9eeb8d26c494d1f1e13a943408ff6badf78025218",
        Shape(inputs: 49, outputs: 2): "3534fc22d19956fe1f1f897f316cf37310350a1678e58dc84a2cfce6989f449c",
    ]
}
