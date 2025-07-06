import Testing
@testable import WhooshingServer
import Vapor
import Foundation
import WhooshingClient

@Suite("环境变量解析测试集")
struct EnvironmentParsingTests {
    
    @Test("测试环境变量读取")
    func testEnvironmentDetect() async throws {
        let project = try Environment.Config.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
            "WHOOSHING_API_SERVICE_NAME": "Testing Project",
            "WHOOSHING_API_SERVICE_PORT": "7777",
            "WHOOSHING_API_SERVICE_DOMAIN": "testing.whooshing.space",
            "WHOOSHING_API_SERVICE_DB_COUNT": "2",
            "WHOOSHING_API_SERVICE_MANAGER_URL": "https://example.com",
            "WHOOSHING_API_SERVICE_HOSTNAME": "localhost",
            "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
            "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
            "WHOOSHING_API_SERVICE_DB_1_USER": "woo",
            "WHOOSHING_API_SERVICE_DB_1_PASSWORD": "woo_test",
            "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
            "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
            "WHOOSHING_API_SERVICE_DB_2_USER": "woowoo",
            "WHOOSHING_API_SERVICE_DB_2_PASSWORD": "woo_testwoo_test",
        ][key] }
        #expect(project.name == "Testing Project")
        #expect(project.domain == "testing.whooshing.space")
        #expect(project.port == 7777)
        #expect(project.hostname == "localhost")
        #expect(project.databases.count == 2)
        #expect(project.managerUrl.absoluteString == "https://example.com")
        #expect(project.databases[0].name == "testdb")
        #expect(project.databases[0].port == 5432)
        #expect(project.databases[0].user == "woo")
        #expect(project.databases[0].password == "woo_test")
        #expect(project.databases[1].name == "testdb_2")
        #expect(project.databases[1].port == 6000)
        #expect(project.databases[1].user == "woowoo")
        #expect(project.databases[1].password == "woo_testwoo_test")
    }
    
    @Test("测试环境变量读取2")
    func testEnvironmentDetect2() async throws {
        let project = try Environment.Config.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
            "WHOOSHING_API_SERVICE_NAME": "Testing Project",
            "WHOOSHING_API_SERVICE_PORT": "7777",
            "WHOOSHING_API_SERVICE_DB_COUNT": "2",
            "WHOOSHING_API_SERVICE_MANAGER_URL": "https://example.com",
            "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
            "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
            "WHOOSHING_API_SERVICE_DB_1_USER": "woo",
            "WHOOSHING_API_SERVICE_HOSTNAME": "127.0.0.1",
            "WHOOSHING_API_SERVICE_DB_1_PASSWORD": "woo_test",
            "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
            "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
            "WHOOSHING_API_SERVICE_DB_2_USER": "woowoo",
            "WHOOSHING_API_SERVICE_DB_2_PASSWORD": "woo_testwoo_test",
        ][key] }
        #expect(project.name == "Testing Project")
        #expect(project.domain == nil)
        #expect(project.port == 7777)
        #expect(project.hostname == "127.0.0.1")
        #expect(project.databases.count == 2)
        #expect(project.managerUrl.absoluteString == "https://example.com")
        #expect(project.databases[0].name == "testdb")
        #expect(project.databases[0].port == 5432)
        #expect(project.databases[0].user == "woo")
        #expect(project.databases[0].password == "woo_test")
        #expect(project.databases[1].name == "testdb_2")
        #expect(project.databases[1].port == 6000)
        #expect(project.databases[1].user == "woowoo")
        #expect(project.databases[1].password == "woo_testwoo_test")
    }
    
    @Test("测试环境变量读取3")
    func testEnvironmentDetect3() async throws {
        #expect(throws: Environment.Errcase.ErrType.self, performing: {
            let _ = try Environment.Config.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
                "WHOOSHING_API_SERVICE_NAME": "Testing Project",
                "WHOOSHING_API_SERVICE_DB_COUNT": "3",
                "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
                "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
                "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
                "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
                "WHOOSHING_API_SERVICE_DB_3_NAME": "testdb_3",
            ][key] }
        })
    }
    
    @Test("测试环境变量读取4")
    func testEnvironmentDetect4() async throws {
        #expect(throws: Environment.Errcase.ErrType.self, performing: {
            let _ = try Environment.Config.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
                "WHOOSHING_API_SERVICE_NAME": "Testing Project",
                "WHOOSHING_API_SERVICE_DB_COUNT": "3",
                "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
                "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
                "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
                "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
                "WHOOSHING_API_SERVICE_DB_3_NAME": "testdb_3",
                "WHOOSHING_API_SERVICE_DB_3_PORT": "HELLOWORLD!",
            ][key] }
        })
    }
}
