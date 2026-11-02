import Foundation
import Testing
@testable import SalterCore

@Suite struct LineBufferTests {
    @Test func splitsLinesAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("a\nb".utf8)) == ["a"])
        #expect(buffer.append(Data("c\r\nd\n".utf8)) == ["bc", "d"])
        #expect(buffer.flush() == nil)
        #expect(buffer.append(Data("tail".utf8)).isEmpty)
        #expect(buffer.flush() == "tail")
    }

    @Test func carriageReturnEndsLine() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("10%\r20%\r".utf8)) == ["10%", "20%"])
        #expect(buffer.append(Data("a\r".utf8)) == ["a"])
        #expect(buffer.append(Data("\nb\r\n".utf8)) == ["b"])
        #expect(!buffer.hasPending)
        _ = buffer.append(Data("x".utf8))
        #expect(buffer.hasPending)
    }

    @Test func flushesVeryLongLinesWithoutNewline() {
        var buffer = LineBuffer()
        let lines = buffer.append(Data(repeating: 0x78, count: 70_000))
        #expect(lines.count == 1)
        #expect(lines.first?.count == 70_000)
        #expect(buffer.flush() == nil)
    }
}
