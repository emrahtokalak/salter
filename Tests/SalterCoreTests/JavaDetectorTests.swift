import Foundation
import Testing
@testable import SalterCore

@Suite struct JavaDetectorTests {
    let springPom = "<project><build><plugins><plugin><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build></project>"

    @Test func mavenSpringBootWithWrapper() throws {
        let repo = try makeRepo("orders", [
            "pom.xml": springPom, "mvnw": "#!/bin/sh\n",
            "src/main/resources/application.properties": "spring.application.name=orders\nserver.port = 8085\n",
        ])
        let r = JavaDetector.detect(repo: repo)
        let s = try #require(r.services.first)
        #expect(r.services.count == 1)
        #expect(s.definition.command == [repo.appendingPathComponent("mvnw").path, "spring-boot:run"])
        #expect(s.definition.name == "spring-boot")
        #expect(s.source == .manifest("java:pom.xml"))
        #expect(s.definition.portHint == 8085)
        #expect(r.ecosystems == [.java])
    }

    @Test func mavenExecWithoutWrapper() throws {
        let repo = try makeRepo("cli", ["pom.xml": "<plugin><artifactId>exec-maven-plugin</artifactId></plugin>"])
        let s = try #require(JavaDetector.detect(repo: repo).services.first)
        #expect(s.definition.command == ["mvn", "exec:java"])
        #expect(s.definition.name == "exec")
        #expect(s.definition.portHint == nil)
    }

    @Test func mavenWithoutPluginSkipped() throws {
        let repo = try makeRepo("lib", ["pom.xml": "<project/>"])
        let r = JavaDetector.detect(repo: repo)
        #expect(r.services.isEmpty)
        #expect(r.skipped == [SkippedConfig(name: "pom.xml", reason: "çalıştırma eklentisi bulunamadı (spring-boot / exec)")])
    }

    @Test func gradleKtsApplication() throws {
        let repo = try makeRepo("app", ["build.gradle.kts": "plugins {\n    kotlin(\"jvm\") version \"2.0.0\"\n    application\n}\n"])
        let s = try #require(JavaDetector.detect(repo: repo).services.first)
        #expect(s.definition.command == ["gradle", "run"])
        #expect(s.definition.name == "run")
        #expect(s.source == .manifest("java:build.gradle.kts"))
    }

    @Test func gradleSpringBootYamlPort() throws {
        let repo = try makeRepo("web", [
            "build.gradle": "plugins {\n  id 'org.springframework.boot' version '3.3.0'\n}\n", "gradlew": "#!/bin/sh\n",
            "src/main/resources/application.yml": "spring:\n  application:\n    name: web\nserver:\n  port: 9090\n",
        ])
        let s = try #require(JavaDetector.detect(repo: repo).services.first)
        #expect(s.definition.command == [repo.appendingPathComponent("gradlew").path, "bootRun"])
        #expect(s.definition.portHint == 9090)
    }

    @Test func gradleWithoutPluginSkipped() throws {
        let repo = try makeRepo("lib", ["build.gradle": "plugins { id 'java-library' }\n"])
        #expect(JavaDetector.detect(repo: repo).skipped == [
            SkippedConfig(name: "build.gradle", reason: "çalıştırma eklentisi bulunamadı (spring-boot / application)"),
        ])
    }

    @Test func springBootDefaultsTo8080() throws {
        let repo = try makeRepo("svc", ["pom.xml": springPom])
        #expect(JavaDetector.detect(repo: repo).services.first?.definition.portHint == 8080)
    }
}
