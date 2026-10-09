import Foundation
import Testing
@testable import DevLauncherCore

@Suite struct ANSIParserTests {
    @Test func plainTextIsOneUnstyledSpan() {
        #expect(ANSIParser.parse("hello") == [ANSISpan(text: "hello", style: ANSIStyle())])
        #expect(ANSIParser.parse("").isEmpty)
    }

    @Test func colorsAndReset() {
        #expect(ANSIParser.parse("\u{1B}[32mINFO\u{1B}[0m: ok") == [
            ANSISpan(text: "INFO", style: ANSIStyle(foreground: .standard(2))),
            ANSISpan(text: ": ok", style: ANSIStyle()),
        ])
        #expect(ANSIParser.parse("\u{1B}[1;91mERR") == [
            ANSISpan(text: "ERR", style: ANSIStyle(foreground: .bright(1), bold: true)),
        ])
    }

    @Test func extendedColorsAndIgnoredBackground() {
        #expect(ANSIParser.parse("\u{1B}[38;5;208mX\u{1B}[38;2;1;2;3mY\u{1B}[48;5;1;39mZ") == [
            ANSISpan(text: "X", style: ANSIStyle(foreground: .palette(208))),
            ANSISpan(text: "Y", style: ANSIStyle(foreground: .rgb(1, 2, 3))),
            ANSISpan(text: "Z", style: ANSIStyle()),
        ])
    }

    @Test func stripsOtherEscapeSequences() {
        #expect(ANSIParser.strip("\u{1B}[2Kline\u{1B}[1A") == "line")
        #expect(ANSIParser.strip("\u{1B}]8;;http://x\u{07}link\u{1B}]8;;\u{1B}\\ done") == "link done")
        #expect(ANSIParser.strip("a\rb\u{07}c\td") == "abc\td")
    }
}

@MainActor @Suite struct LogBufferTests {
    @Test func trimsToCapacityInBatches() {
        let buffer = LogBuffer(capacity: 10)
        buffer.append(.stdout, (0..<11).map(String.init))
        #expect(buffer.lines.count == 11)
        buffer.append(.stderr, ["11"])
        #expect(buffer.lines.count == 10)
        #expect(buffer.lines.first?.id == 2)
        #expect(buffer.lines.last?.text == "11")
        #expect(buffer.lines.last?.kind == .stderr)
        buffer.clear()
        #expect(buffer.lines.isEmpty)
        buffer.append(.system, ["x"])
        #expect(buffer.lines.first?.id == 12)
    }
}

@Suite struct LogFileWriterTests {
    @Test func writesAndRotates() throws {
        let dir = try makeTempDirectory()
        let url = dir.appendingPathComponent("svc.log")
        let writer = LogFileWriter(url: url, maxBytes: 20)
        writer.write(["0123456789"])
        writer.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == "0123456789\n")
        writer.write(["abcdefghij"])
        writer.flush()
        #expect(try String(contentsOf: url, encoding: .utf8) == "abcdefghij\n")
        #expect(try String(contentsOf: URL(fileURLWithPath: url.path + ".1"), encoding: .utf8) == "0123456789\n")
    }

    @Test func serviceLogFileNames() {
        let dir = URL(fileURLWithPath: "/logs")
        #expect(LogFileWriter.url(forService: "docs-api/api-uvicorn-debug", directory: dir).path == "/logs/docs-api-api-uvicorn-debug.log")
    }
}
