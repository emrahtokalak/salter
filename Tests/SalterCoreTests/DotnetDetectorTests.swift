import Foundation
import Testing
@testable import SalterCore

@Suite struct DotnetDetectorTests {
    @Test func webProjectWithLaunchSettingsPort() throws {
        let repo = try makeRepo("shop", [
            "src/Api/Api.csproj": #"<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>"#,
            "src/Api/Properties/launchSettings.json": """
            { // comment
              "profiles": {
                "https": { "commandName": "Project", "applicationUrl": "https://localhost:7001;http://localhost:5001" },
                "IIS Express": { "commandName": "IISExpress" },
              }
            }
            """,
        ])
        let r = DotnetDetector.detect(repo: repo)
        let s = try #require(r.services.first)
        #expect(r.services.count == 1)
        #expect(s.definition.command == ["dotnet", "run", "--project", "src/Api/Api.csproj"])
        #expect(s.definition.name == "Api")
        #expect(s.source == .manifest("dotnet:src/Api/Api.csproj"))
        #expect(s.definition.cwd == repo.path)
        #expect(s.definition.portHint == 7001)
        #expect(r.ecosystems == [.dotnet])
    }

    @Test func consoleExe() throws {
        let repo = try makeRepo("tool", [
            "Tool.csproj": "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><OutputType>Exe</OutputType></PropertyGroup></Project>",
        ])
        let s = try #require(DotnetDetector.detect(repo: repo).services.first)
        #expect(s.definition.command == ["dotnet", "run", "--project", "Tool.csproj"])
        #expect(s.definition.portHint == nil)
    }

    @Test func testProjectsExcluded() throws {
        let web = #"<Project Sdk="Microsoft.NET.Sdk.Web"></Project>"#
        let repo = try makeRepo("shop", [
            "tests/Api.Tests/Api.Tests.csproj": web,
            "tests/Api.Test/Api.Test.csproj": web,
            "tests/Flagged/Flagged.csproj": "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><OutputType>Exe</OutputType><IsTestProject>true</IsTestProject></PropertyGroup></Project>",
            "tests/Ref/Ref.csproj": "<Project Sdk=\"Microsoft.NET.Sdk\"><PropertyGroup><OutputType>Exe</OutputType></PropertyGroup><ItemGroup><PackageReference Include=\"Microsoft.NET.Test.Sdk\" /></ItemGroup></Project>",
            "src/Worker/Worker.csproj": #"<Project Sdk="Microsoft.NET.Sdk.Worker"></Project>"#,
        ])
        #expect(DotnetDetector.detect(repo: repo).services.map(\.definition.name) == ["Worker"])
    }

    @Test func classLibraryIgnored() throws {
        let repo = try makeRepo("lib", ["Lib/Lib.csproj": #"<Project Sdk="Microsoft.NET.Sdk"></Project>"#, "Lib/obj/X.csproj": "<OutputType>Exe</OutputType>"])
        let r = DotnetDetector.detect(repo: repo)
        #expect(r.services.isEmpty)
        #expect(r.ecosystems.isEmpty)
    }

    @Test func nameEndingInTestWithoutDotIsKept() throws {
        let repo = try makeRepo("net", ["src/SpeedTest/SpeedTest.csproj": #"<Project Sdk="Microsoft.NET.Sdk.Web"></Project>"#])
        #expect(DotnetDetector.detect(repo: repo).services.map(\.definition.name) == ["SpeedTest"])
    }
}
