import Testing
@testable import widgets

struct NumberedWordTests {
    @Test
    func `Descriptions omit the word`() {
        let word = NumberedWord(position: 1, text: "abandon")
        var dumped = ""
        dump(word, to: &dumped)

        #expect(String(describing: word) == "NumberedWord")
        #expect(String(reflecting: word) == "NumberedWord")
        #expect(dumped == "- NumberedWord\n")
    }
}
