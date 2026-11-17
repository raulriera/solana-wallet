import Encoding
import Testing

struct HexTests {
    private static let vectors: [([UInt8], String)] = [
        ([], ""),
        ([0x00], "00"),
        ([0x0f], "0f"),
        ([0xa0], "a0"),
        ([0xff, 0x00, 0x7e], "ff007e"),
        ([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef], "0123456789abcdef"),
    ]

    @Test(arguments: vectors)
    func `Hex writes each byte as two lowercase digits and reads each pair back as one byte`(
        bytes: [UInt8],
        text: String
    ) {
        #expect(Hex.encode(bytes) == text)
        #expect(Hex.decode(text) == bytes)
    }

    @Test(arguments: [
        "0", "abc", String(repeating: "7e", count: 32) + "7", "AB", "aB", "0g", "0x00", " 0", "00\n", "é", "٠١", "ａｂ",
    ])
    func `Hex decoding rejects text that isn't pairs of lowercase digits`(_ text: String) {
        #expect(Hex.decode(text) == nil)
    }
}
