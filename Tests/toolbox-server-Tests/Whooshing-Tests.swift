import Testing
@testable import WhooshingServer
import Vapor
import Foundation

@Suite("Whooshing 工具测试")
struct WhooshingTests {
    
    @Test("测试环境变量读取") func testEnvironmentDetect() async throws {
        let project = try #require(Env.Project.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
            "WHOOSHING_API_SERVICE_NAME": "Testing Project",
            "WHOOSHING_API_SERVICE_PORT": "7777",
            "WHOOSHING_API_SERVICE_DOMAIN": "testing.whooshing.space",
            "WHOOSHING_API_SERVICE_DB_COUNT": "2",
            "WHOOSHING_API_SERVICE_MANAGER_URL": "https://example.com",
            "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
            "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
            "WHOOSHING_API_SERVICE_DB_1_USER": "woo",
            "WHOOSHING_API_SERVICE_DB_1_PASSWORD": "woo_test",
            "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
            "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
            "WHOOSHING_API_SERVICE_DB_2_USER": "woowoo",
            "WHOOSHING_API_SERVICE_DB_2_PASSWORD": "woo_testwoo_test",
        ][key] })
        #expect(project.name == "Testing Project")
        #expect(project.domain == "testing.whooshing.space")
        #expect(project.port == 7777)
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
    
    @Test("测试环境变量读取2") func testEnvironmentDetect2() async throws {
        let project = try #require(Env.Project.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
            "WHOOSHING_API_SERVICE_NAME": "Testing Project",
            "WHOOSHING_API_SERVICE_PORT": "7777",
            "WHOOSHING_API_SERVICE_DB_COUNT": "2",
            "WHOOSHING_API_SERVICE_MANAGER_URL": "https://example.com",
            "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
            "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
            "WHOOSHING_API_SERVICE_DB_1_USER": "woo",
            "WHOOSHING_API_SERVICE_DB_1_PASSWORD": "woo_test",
            "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
            "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
            "WHOOSHING_API_SERVICE_DB_2_USER": "woowoo",
            "WHOOSHING_API_SERVICE_DB_2_PASSWORD": "woo_testwoo_test",
        ][key] })
        #expect(project.name == "Testing Project")
        #expect(project.domain == nil)
        #expect(project.port == 7777)
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
    
    @Test("测试环境变量读取3") func testEnvironmentDetect3() async throws {
        do {
            let _ = try #require(Env.Project.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
                "WHOOSHING_API_SERVICE_NAME": "Testing Project",
                "WHOOSHING_API_SERVICE_DB_COUNT": "3",
                "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
                "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
                "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
                "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
                "WHOOSHING_API_SERVICE_DB_3_NAME": "testdb_3",
            ][key] })
            #expect(Bool(false), "错误的环境变量仍然成功运行了")
        } catch {
            #expect(Bool(true))
        }
    }
    
    @Test("测试环境变量读取4") func testEnvironmentDetect4() async throws {
        do {
            let _ = try #require(Env.Project.parse(prefix: "WHOOSHING_API_SERVICE") { key in [
                "WHOOSHING_API_SERVICE_NAME": "Testing Project",
                "WHOOSHING_API_SERVICE_DB_COUNT": "3",
                "WHOOSHING_API_SERVICE_DB_1_NAME": "testdb",
                "WHOOSHING_API_SERVICE_DB_1_PORT": "5432",
                "WHOOSHING_API_SERVICE_DB_2_NAME": "testdb_2",
                "WHOOSHING_API_SERVICE_DB_2_PORT": "6000",
                "WHOOSHING_API_SERVICE_DB_3_NAME": "testdb_3",
                "WHOOSHING_API_SERVICE_DB_3_PORT": "HELLOWORLD!",
            ][key] })
            #expect(Bool(false), "错误的环境变量仍然成功运行了")
        } catch {
            #expect(Bool(true))
        }
    }

    @Test("测试 ClientResponse 与 Data 互转") func testClientResponseToData() async throws {
        var origin = "HTTP/1.1 200 OK\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 13\r\n\r\nHello, world!"
        do {
            let res = try ClientResponse(data: .init(data: origin.data(using: .utf8)!))
            origin = origin.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(res.description == origin)
        } catch let err {
            print(err)
            #expect(Bool(false))
        }
    }
}
