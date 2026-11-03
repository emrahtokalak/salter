import Foundation
import Testing
@testable import SalterCore

@Suite struct LogLineParserTests {
    func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)!
    }

    // MARK: JSON

    @Test func jsonExtractsMessageLevelTimeAndFields() {
        let p = LogLineParser.parse(#"{"@timestamp":"2026-11-02T20:27:37.123Z","level":"info","message":"application_started","method":"hybrid"}"#)
        #expect(p.isStructured)
        #expect(p.message == "application_started")
        #expect(p.level == .info)
        #expect(p.time == iso("2026-11-02T20:27:37.123Z"))
        #expect(p.fields == [LogField(key: "method", value: "hybrid")])
    }

    @Test func jsonFieldVariants() {
        #expect(LogLineParser.parse(#"{"msg":"a","log_level":"WARNING"}"#).level == .warn)
        #expect(LogLineParser.parse(#"{"msg":"a","severity":"ERROR"}"#).level == .error)
        #expect(LogLineParser.parse(#"{"msg":"a","ts":1793651994.5}"#).time == Date(timeIntervalSince1970: 1793651994.5))
        #expect(LogLineParser.parse(#"{"msg":"a","time":1793651994500}"#).time == Date(timeIntervalSince1970: 1793651994.5))
        #expect(LogLineParser.parse(#"{"msg":"a","level":50}"#).level == .error)
        #expect(LogLineParser.parse(#"{"msg":"a","level":40}"#).level == .warn)
        #expect(LogLineParser.parse(#"{"msg":"a","level":30}"#).level == .info)
        #expect(LogLineParser.parse(#"{"msg":"a","level":20}"#).level == .debug)
        #expect(LogLineParser.parse(#"{"msg":"a","level":10}"#).level == .trace)
    }

    @Test func jsonDropsFieldsEqualToMessage() {
        #expect(LogLineParser.parse(#"{"msg":"x","event_type":"x","a":1}"#).fields == [LogField(key: "a", value: "1")])
    }

    @Test func jsonNestedValuesRenderAsCompactJSON() {
        #expect(LogLineParser.parse(#"{"msg":"x","ctx":{"k":1}}"#).fields == [LogField(key: "ctx", value: #"{"k":1}"#)])
    }

    @Test func jsonFieldsSortedByKey() {
        let p = LogLineParser.parse(#"{"msg":"x","b":"2","a":"1","c":"3"}"#)
        #expect(p.fields.map(\.key) == ["a", "b", "c"])
    }

    @Test func nonObjectOrInvalidJSONIsPlain() {
        for raw in ["[1,2]", #"{"a":"#] {
            let p = LogLineParser.parse(raw)
            #expect(!p.isStructured)
            #expect(p.message == raw)
        }
        let number = LogLineParser.parse(#"{"msg": 42}"#)
        #expect(number.isStructured)
        #expect(number.message == "42")
        #expect(number.fields.isEmpty)
        let null = LogLineParser.parse(#"{"msg": null}"#)
        #expect(null.isStructured)
        #expect(null.message == "")
        #expect(null.fields.isEmpty)
    }

    @Test func ansiPrefixedJSONIsParsed() {
        #expect(LogLineParser.parse("\u{1B}[0m{\"msg\":\"hi\"}").message == "hi")
    }

    // MARK: logfmt

    @Test func logfmtSlogLine() {
        let p = LogLineParser.parse(#"time=2026-11-02T23:27:37.000+03:00 level=WARN msg="search failed" dropped_total=2"#)
        #expect(p.isStructured)
        #expect(p.level == .warn)
        #expect(p.message == "search failed")
        #expect(p.fields == [LogField(key: "dropped_total", value: "2")])
        #expect(p.time == iso("2026-11-02T20:27:37.000Z"))
    }

    @Test func textWithEqualsButNoMsgIsPlain() {
        #expect(!LogLineParser.parse("a=b c=d").isStructured)
    }

    // MARK: plain text

    func plain(_ raw: String) -> LogLevel? {
        let p = LogLineParser.parse(raw)
        #expect(!p.isStructured)
        #expect(p.time == nil)
        #expect(p.message == raw)
        return p.level
    }

    @Test func uvicornPrefix() { #expect(plain("INFO:     Started server process [123]") == .info) }
    @Test func bracketLevel() { #expect(plain("[WARN] slow") == .warn) }
    @Test func springBootToken() {
        #expect(plain("2026-11-02 23:27:37.123  ERROR 1234 --- [main] o.s.Foo : boom") == .error)
    }
    @Test func levelEqualsInText() { #expect(plain("foo level=debug bar") == .debug) }
    @Test func tokenAfter60CharsIgnored() { #expect(plain(String(repeating: "x", count: 70) + " ERROR") == nil) }
    @Test func noLevel() { #expect(plain("GET /health 200") == nil) }
    @Test func wordInsideIdentifierIgnored() { #expect(plain("ERRORS_TOTAL=3") == nil) }
}
