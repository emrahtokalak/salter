import Foundation
import Testing
@testable import SalterCore

@Suite struct MiniTOMLTests {
    @Test func parsesTablesAndArrayTables() {
        let t = MiniTOML.parse("""
        [package]
        name = "api"
        autobins = false
        version.workspace = true

        [[bin]]
        name = 'srv'
        path = "src/srv.rs"

        [[bin]]
        name = "tool"
        """)
        #expect(t.tables["package"]?["name"] == .string("api"))
        #expect(t.tables["package"]?["autobins"] == .bool(false))
        #expect(t.arrayTables["bin"]?.count == 2)
        #expect(t.arrayTables["bin"]?[0]["path"] == .string("src/srv.rs"))
        #expect(t.arrayTables["bin"]?[1]["name"] == .string("tool"))
    }

    @Test func parsesCommentsAndMultilineArrays() {
        let t = MiniTOML.parse("""
        # top
        [workspace] # trailing
        members = [
          "a", # first
          "crates/*",
        ]
        exclude = ["x#y"]
        resolver = "2" # comment
        """)
        #expect(t.tables["workspace"]?["members"] == .strings(["a", "crates/*"]))
        #expect(t.tables["workspace"]?["exclude"] == .strings(["x#y"]))
        #expect(t.tables["workspace"]?["resolver"] == .string("2"))
    }

    @Test func parsesCrlf() {
        let t = MiniTOML.parse("[package]\r\nname = \"api\"\r\n")
        #expect(t.tables["package"]?["name"] == .string("api"))
    }
}
