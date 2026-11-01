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
        Shape(inputs: 1, outputs: 2): "63fec3e6284bf47f0095803859efffd5a948629501622c3227042c6718ba19d5",
        Shape(inputs: 1, outputs: 4): "36f94d0133e555e3860e045580dcc2f0d7b5c8968946b14c5be7d01adb0e0055",
        Shape(inputs: 1, outputs: 8): "6910a9621bb9452e5925d0e790b74e6d27f3b3a1fe1d288305cde48171957522",
        Shape(inputs: 2, outputs: 2): "5c6d38f60464c7d3704b2b1edd93ac6c826d0df8827293884d7b30690fc204f8",
        Shape(inputs: 2, outputs: 4): "1fc6a07b1e968dec87592dbf58ecbe92c0c5d7dd0e5e589c08dbf80796224f2b",
        Shape(inputs: 1, outputs: 16): "6b3d6d3a0cf6d3befa4fab316d3190e4c4ee1867c6d9de71a2de8cbb1bc2c383",
        Shape(inputs: 2, outputs: 8): "c33f83f029f46e0d1f977eea479aa62d475985db2ffda509297d4b297430fac3",
        Shape(inputs: 3, outputs: 2): "1da53f2a56462417253b26cb0effd9d4fbb8a11bda720e7921c49cda7e5e6316",
        Shape(inputs: 3, outputs: 4): "35cfb48e07cd38f3c1b49e81f20ee4c74940f6f6c7fc7230ece1c17ac56f45ea",
        Shape(inputs: 2, outputs: 16): "e284fc565ad50220159af043b3ef4395d00704dff4f4585eed46a0b540b1fcf5",
        Shape(inputs: 3, outputs: 8): "01f87529ca7ffd1d7d91fb74e5eb7c6222a3a7ad62dfa479dc7e07bd96af01ce",
        Shape(inputs: 4, outputs: 2): "967d32c97e0a1e1150cd3f5e3a69bf86f1beb44a1f1143563f42e4ee98ce7c6f",
        Shape(inputs: 4, outputs: 4): "049cf9701bec7a414bcd064351acd3f10a2f4c69aaa10953d355c0513a302070",
        Shape(inputs: 4, outputs: 8): "7df8bf5e2e8baf9bf4b8340c21c852707c45ee07cf0bef064f24d7a90857910b",
        Shape(inputs: 5, outputs: 2): "eb62fdaf21552d00292ba6513d0b5aa49b93db1975b909eecbe92d2625e09aa5",
        Shape(inputs: 5, outputs: 4): "ef1729f5d24b5a7d0cf0f906e71e3e63ab31ae02491ef2140c7e3b7e7b68f1fc",
        Shape(inputs: 4, outputs: 16): "c186822727ca00edbd96ba4db248d8629f08cc2281a9d3805d270ee2f6fb3098",
        Shape(inputs: 5, outputs: 8): "04cde7cd928e58001b5ad3bb1213aa789eec2da7bc0215c9bb445a17321f2bea",
        Shape(inputs: 6, outputs: 2): "d86a46274b6558c4bb13bce72a8f511f6b8f3c399125449ac67731e2bdcebfee",
        Shape(inputs: 6, outputs: 4): "2b523a9575c6e3263898a9afa2f3a3ee24f9f74b27baa76e8f6676cf988a0861",
        Shape(inputs: 5, outputs: 16): "be93ae4e719a890e8f5e68348ec891a691e9b44127271972dd1a30ea93487e54",
        Shape(inputs: 6, outputs: 8): "90011b7811805a1fe784a99062088fb5a04c4169b9c1a59f30e8b40fee864dd7",
        Shape(inputs: 8, outputs: 2): "c10606362880adb6747617f127aaffa08a2df314146d7f996f5c9de659edfb7b",
        Shape(inputs: 8, outputs: 4): "d44b087de72260f6149e14098ba458ab44e565ca4c9e3ed575f3d4b5bd476b47",
        Shape(inputs: 8, outputs: 8): "3fce685c5cfe6bc4ed1c11a74c4b9168c8d99e5b0cd2229a1217c3918c791a94",
        Shape(inputs: 8, outputs: 16): "6b03e0b636de7a4722a1829aa103919ed6ce67defe47c32d432eb09d73a4a188",
        Shape(inputs: 12, outputs: 2): "f97bd750648a767ea2f660f713f1e9139d7355f41f26dce274f50ac9bc3a1b9c",
        Shape(inputs: 12, outputs: 4): "79625237ff8d673999cf3c78b5998d53ca9acc838d3d7bccbbb288ba3a0947af",
        Shape(inputs: 12, outputs: 8): "a6caf80326c6fc3ea4f987aa37c76e9dd9532e82cdf65f1bef50c14abc5a2dda",
        Shape(inputs: 16, outputs: 2): "c1567923bb8195606eb66cda4ddcff0ab7145de1b89c0f8c926d41e7e41fda12",
        Shape(inputs: 16, outputs: 4): "7b0c7f94baff6297bb3158359eec1b4489b28e4eda20347c1ed24b06847a8e44",
        Shape(inputs: 16, outputs: 8): "60269cff6c59500a50cb5b6539a3aab3fc6c102a6f216e5ff4bafcb8c7a9fcfd",
        Shape(inputs: 24, outputs: 2): "b5b33814223d17e9b1db4a24268b5eda24af36a9af8062dfb08e6a1391346ac4",
        Shape(inputs: 24, outputs: 4): "97d6b9a29667cf9388a964fdc2e81da09a8dffc50a7da7d1910a79393c6bd470",
        Shape(inputs: 32, outputs: 2): "785153ba7ad8cc3a8a16e54ebbbbb6d001635f2e81bc5b4785803b860ce03a87",
        Shape(inputs: 40, outputs: 2): "e5ba9e619453c669848c111607665b610d7b924826ce5580848dddf2a31da9de",
        Shape(inputs: 48, outputs: 2): "644482bbb1fab113ee9a9c1b91f884ebfe6a5864e004e641ff200a4b170afcc6",
        Shape(inputs: 49, outputs: 2): "53cbbd93ac9c53a87d5883b15b3b81c88afc1e9f45a86c1e63e24193c75b2774",
    ]
}
