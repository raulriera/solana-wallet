@testable import Encoding

enum DERVectors {
    private static let jones: [UInt8] = [0x4a, 0x6f, 0x6e, 0x65, 0x73]

    private static let visibleString = DER.Identifier(tagWithNumber: 26, tagClass: .universal)

    private static let ia5String = DER.Identifier(tagWithNumber: 22, tagClass: .universal)

    private static let applicationJones = DER(
        identifier: DER.Identifier(tagWithNumber: 3, tagClass: .application),
        content: .primitive(jones)
    )

    static let canonical: [([UInt8], DER)] = [
        ([0x01, 0x01, 0xff], DER(identifier: .boolean, content: .primitive([0xff]))),
        ([0x02, 0x01, 0x00], DER(identifier: .integer, content: .primitive([0x00]))),
        ([0x02, 0x01, 0x80], DER(identifier: .integer, content: .primitive([0x80]))),
        ([0x02, 0x02, 0x00, 0x80], DER(identifier: .integer, content: .primitive([0x00, 0x80]))),
        (
            [0x03, 0x07, 0x04, 0x0a, 0x3b, 0x5f, 0x29, 0x1c, 0xd0],
            DER(identifier: .bitString, content: .primitive([0x04, 0x0a, 0x3b, 0x5f, 0x29, 0x1c, 0xd0]))
        ),
        ([0x03, 0x02, 0x01, 0x06], DER(identifier: .bitString, content: .primitive([0x01, 0x06]))),
        ([0x04, 0x00], DER(identifier: .octetString, content: .primitive([]))),
        ([0x05, 0x00], DER(identifier: .null, content: .primitive([]))),
        ([0x06, 0x03, 0x88, 0x37, 0x03], DER(identifier: .objectIdentifier, content: .primitive([0x88, 0x37, 0x03]))),
        ([0x30, 0x00], DER(identifier: .sequence, content: .constructed([]))),
        ([0x31, 0x00], DER(identifier: .set, content: .constructed([]))),
        (
            [0x30, 0x0a, 0x16, 0x05, 0x53, 0x6d, 0x69, 0x74, 0x68, 0x01, 0x01, 0xff],
            DER(
                identifier: .sequence,
                content: .constructed([
                    DER(identifier: ia5String, content: .primitive([0x53, 0x6d, 0x69, 0x74, 0x68])),
                    DER(identifier: .boolean, content: .primitive([0xff])),
                ])
            )
        ),
        (
            [0x30, 0x0a, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03],
            DER(
                identifier: .sequence,
                content: .constructed([
                    DER(
                        identifier: .objectIdentifier,
                        content: .primitive([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03])
                    )
                ])
            )
        ),
        (
            [0x30, 0x06, 0x01, 0x01, 0xff, 0x02, 0x01, 0x00],
            DER(
                identifier: .sequence,
                content: .constructed([
                    DER(identifier: .boolean, content: .primitive([0xff])),
                    DER(identifier: .integer, content: .primitive([0x00])),
                ])
            )
        ),
        (
            [0xa0, 0x03, 0x02, 0x01, 0x02],
            DER(
                identifier: DER.Identifier(tagWithNumber: 0, tagClass: .contextSpecific),
                content: .constructed([DER(identifier: .integer, content: .primitive([0x02]))])
            )
        ),
        ([0x1a, 0x05] + jones, DER(identifier: visibleString, content: .primitive(jones))),
        ([0x43, 0x05] + jones, applicationJones),
        (
            [0xa2, 0x07, 0x43, 0x05] + jones,
            DER(
                identifier: DER.Identifier(tagWithNumber: 2, tagClass: .contextSpecific),
                content: .constructed([applicationJones])
            )
        ),
        (
            [0x67, 0x07, 0x43, 0x05] + jones,
            DER(
                identifier: DER.Identifier(tagWithNumber: 7, tagClass: .application),
                content: .constructed([applicationJones])
            )
        ),
        (
            [0x82, 0x05] + jones,
            DER(identifier: DER.Identifier(tagWithNumber: 2, tagClass: .contextSpecific), content: .primitive(jones))
        ),
        (
            [0x50, 0x00],
            DER(identifier: DER.Identifier(tagWithNumber: 16, tagClass: .application), content: .primitive([]))
        ),
        (
            [0xde, 0x01, 0x2a],
            DER(identifier: DER.Identifier(tagWithNumber: 30, tagClass: .private), content: .primitive([0x2a]))
        ),
        (
            [0xbe, 0x00],
            DER(identifier: DER.Identifier(tagWithNumber: 30, tagClass: .contextSpecific), content: .constructed([]))
        ),
        ([0x04, 0x26] + filler(count: 38), DER(identifier: .octetString, content: .primitive(filler(count: 38)))),
        ([0x04, 0x7f] + filler(count: 127), DER(identifier: .octetString, content: .primitive(filler(count: 127)))),
        (
            [0x04, 0x81, 0x80] + filler(count: 128),
            DER(identifier: .octetString, content: .primitive(filler(count: 128)))
        ),
        (
            [0x04, 0x81, 0xc9] + filler(count: 201),
            DER(identifier: .octetString, content: .primitive(filler(count: 201)))
        ),
        (
            [0x04, 0x82, 0x01, 0x00] + filler(count: 256),
            DER(identifier: .octetString, content: .primitive(filler(count: 256)))
        ),
    ]

    static let certificate =
        "MIICiTCCAg6gAwIBAgIUFQXoK61IoW5Q4qGj9HoAx390vHwwCgYIKoZIzj0EAwMwgYExCzAJBgNVBAYTAlVTMRAwDgYDVQQIDAdP"
        + "bnRhcmlvMRAwDgYDVQQHDAdUb3JvbnRvMRAwDgYDVQQKDAdFeGFtcGxlMSUwIwYDVQQLDBxEaXN0aW5ndWlzaGVkIEVuY29kaW5n"
        + "IFJ1bGVzMRUwEwYDVQQDDAxFeGFtcGxlIFJvb3QwHhcNMjYxMDMxMDUyMjM2WhcNMjYxMTAxMDUyMjM2WjCBgTELMAkGA1UEBhMC"
        + "VVMxEDAOBgNVBAgMB09udGFyaW8xEDAOBgNVBAcMB1Rvcm9udG8xEDAOBgNVBAoMB0V4YW1wbGUxJTAjBgNVBAsMHERpc3Rpbmd1"
        + "aXNoZWQgRW5jb2RpbmcgUnVsZXMxFTATBgNVBAMMDEV4YW1wbGUgUm9vdDB2MBAGByqGSM49AgEGBSuBBAAiA2IABIZtZ7dacdId"
        + "kKfMjr2azEfSTuSqYHHbJ/M/jnqsasI+rgSd4+6lwQvWuqpHy1dUe/AITUtrRDBgQKSIgU9Khzj4BR4Xh0WcODub3QjDKm3Ube2o"
        + "IYKCnOQ0ajn4wmB6H6NFMEMwHQYDVR0OBBYEFPUr0N6wARf+KR8WB3QPSP1Mw1rsMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0P"
        + "AQH/BAQDAgEGMAoGCCqGSM49BAMDA2kAMGYCMQCgpEa7BGZ+e4d0vIloUYhSfbKIzf0aqh8dkv/uShfiwk659JkkACTcygMcw0Fp"
        + "XqUCMQC5Ih86v3iizPQcnB4tQoR+/5NpHklCILrr/xtcjAOQqjG6OUidDJV9z5hBAgBtga8="

    static let rsaPublicKey =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmOoZ1RGrWoZVpQ2TIRlMTWn9/9RT9LBSmWEKSmA4+UZT52DS4VmQWxUg"
        + "f460mIYDOll1cmCXN1yBNgaALQcdQIai5j4ZHTfkhdeF/3hWBqIRFseYyoaVH7I1QPkaBn+2/OJU1BK/Ysep+prBjM7oDSUeMd2x"
        + "ujPAsYMeuI651HE9EO/sT4w7DtWc/0lKjAUivL2Hl9IUzvcXCzUwKCtUAlyz6NILVcaLXH5+jFV7dSUH9lHaqMt5xjDcDRy0pU18"
        + "VBkYhJaJMgwEYgSQpfrPmBIHTBLLU0boMEFPqvAPZr/+UYaDauvDTzr4Y2RTrC9xvwOIiRWXXmYY/s7jPVFX9QIDAQAB"

    static func filler(count: Int) -> [UInt8] {
        [UInt8](repeating: 0x5a, count: count)
    }
}
