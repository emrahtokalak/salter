import Foundation
import Testing
@testable import SalterCore

@Suite struct JSONCReaderTests {
    private func parse(_ text: String) throws -> [String: Any] {
        try JSONCReader.object(from: Data(text.utf8))
    }

    @Test func stripsLineAndBlockComments() throws {
        let obj = try parse("""
        {
          // line comment
          "a": 1, /* block
          comment */ "b": 2
        }
        """)
        #expect(obj["a"] as? Int == 1)
        #expect(obj["b"] as? Int == 2)
    }

    @Test func keepsCommentLikeTextInsideStrings() throws {
        let obj = try parse(#"{ "url": "http://x//y", "glob": "a/*b*/c", "q": "say \"//hi\"" }"#)
        #expect(obj["url"] as? String == "http://x//y")
        #expect(obj["glob"] as? String == "a/*b*/c")
        #expect(obj["q"] as? String == #"say "//hi""#)
    }

    @Test func removesTrailingCommasEvenAfterComments() throws {
        let obj = try parse("""
        { "list": [1, 2, // two
        ], "o": { "k": "v", }, }
        """)
        #expect(obj["list"] as? [Int] == [1, 2])
        #expect((obj["o"] as? [String: Any])?["k"] as? String == "v")
    }

    @Test func keepsCommasInsideStrings() throws {
        let obj = try parse(#"{ "s": "a, ]" }"#)
        #expect(obj["s"] as? String == "a, ]")
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: JSONCReader.Error.self) { try parse(#"{ "a": }"#) }
        #expect(throws: JSONCReader.Error.notAnObject) { try parse("[1]") }
    }
}
