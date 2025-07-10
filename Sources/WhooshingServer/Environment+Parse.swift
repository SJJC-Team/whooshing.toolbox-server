import Vapor
import FluentKit
import ErrorHandle
import DataConvertable
import Collections

extension Environment.Config: Environment.Template {
    @inlinable
    static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["name"] = .string
        origin["port"] = .int
        origin["hostname"] = .string
        origin["#domain"] = .string
        origin["#file_storage_dir"] = .string
        origin["manager_url"] = .url
        origin["db_services"] = .dataTemplates(Environment.DBService.self)
    }
    
    @usableFromInline
    init(data: [String: Any], extra: [String: Any]) {
        self.name = data["name"] as! String
        self.port = data["port"] as! Int
        self.hostname = data["hostname"] as! String
        self.dbServices = data["db_services"] as! [Environment.DBService]
        self.domain = data["domain"] as? String
        self.managerUrl = data["manager_url"] as! URL
        self.fileStorageDir = data["file_storage_dir"] as? String
    }
}

extension Environment.DBService: Environment.Template {
    
    @inlinable
    static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["name"] = .string
        origin["port"] = .int
        origin["dbs"] = .dataTemplates(Environment.DB.self)
    }
    
    @usableFromInline
    init(data: [String : Any], extra: [String: Any]) {
        self = Self.init(
            name: data["name"] as! String,
            port: data["port"] as! Int,
            dbParameters: data["dbs"] as! [Environment.DB.Parameter]
        )
    }
}

extension Environment.DB: Environment.Template {
    @inlinable
    static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["name"] = .string
        origin["user"] = .string
        origin["password"] = .string
        origin["file_storage_key"] = .base64Data
    }
    
    @usableFromInline
    init(data: [String : Any], extra: [String : Any]) {
        self = Self.init(
            dbServiceId: extra["name"] as! DatabaseID,
            port: extra["port"] as! Int,
            parameter: .init(
                name: data["name"] as! String,
                user: data["user"] as! String,
                password: data["password"] as! String,
                unsafeTestOnlyHost: nil,
                fileStorageKey: .new(data: data["file_storage_key"] as! Data)
            )
        )
    }
}

extension Environment {
    @inlinable
    static func get(with prefix: String) throws(Errcase.ErrType) -> Config { try .parse(prefix: prefix) }
    
    @usableFromInline
    enum Types {
        case string
        case int
        case stringArr
        case intArr
        case base64String
        case base64Data
        case url
        case uri
        case uuid
        case dataTemplate(Template.Type)
        case dataTemplates(Template.Type)
    }

    @usableFromInline
    protocol Template {
        static var envs: OrderedDictionary<String, Environment.Types> { get }
        static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>)
        init(data: [String: Any], extra: [String: Any])
        init()
    }

    @frozen
    public enum Errcase: String, ErrList {
        case parseFailed = "环境变量解析失败"
        case typeIncorrect = "环境变量配置类型不匹配"
        case missingKey = "环境变量配置字段缺失"
    }
}

extension Environment.Template {
    @inlinable
    static var envs: OrderedDictionary<String, Environment.Types> {
        var res = OrderedDictionary<String, Environment.Types>()
        withEnv(dic: &res)
        return res
    }
}

extension Environment.Template {
    @inlinable
    static func parse(
        prefix: String?,
        getValue: @escaping ((String) -> String?) = { Environment.get($0) },
        extra: [String: Any] = [:]
    ) throws(Environment.Errcase.ErrType) -> Self {
        var values: [String: Any] = [:]
        for (key, v) in Self.envs {
            if key.hasPrefix("#") {
                let key = String(key.dropFirst())
                let k = prefix == nil ? key : "\(prefix!)_\(key.uppercased())"
                values[key] = getValue(k)
                continue
            }
            let k = prefix == nil ? key : "\(prefix!)_\(key.uppercased())"
            let value: String!
            
            switch v {
            case .string, .int, .intArr, .url, .uri, .uuid, .stringArr:
                guard let vv = getValue(k) else {
                    throw Environment.Errcase.missingKey.d(k)
                }
                value = vv
            default: value = nil
            }
            
            switch v {
            case .string:
                values[key] = value
                
            case .stringArr:
                values[key] = value.split(separator: ",").map { String($0) }
                
            case .base64String:
                values[key] = Base64String(value)
                
            case .base64Data:
                values[key] = try required(throws: Environment.Errcase.parseFailed, k) {
                    try Base64String(value).dataRes.get()
                }
                
            case .uri:
                values[key] = URI(string: value)
                
            case .int:
                guard let v = Int(value) else { throw Environment.Errcase.typeIncorrect.d(k) }
                values[key] = v
                
            case .url:
                guard let v = URL(string: value) else { throw Environment.Errcase.typeIncorrect.d(k) }
                values[key] = v
                
            case .uuid:
                guard let v = UUID(uuidString: value) else { throw Environment.Errcase.typeIncorrect.d(k) }
                values[key] = v
                
            case .intArr:
                values[key] = try value.split(separator: ",").map { v throws(Environment.Errcase.ErrType) in
                    guard let v = Int(v) else {
                        throw Environment.Errcase.typeIncorrect.d(k)
                    }
                    return v
                }
                
            case .dataTemplate(let template):
                values[key] = try template.parse(prefix: k, getValue: getValue, extra: values)
                
            case .dataTemplates(let template):
                guard let countStr = getValue(k + "_COUNT") else { throw Environment.Errcase.missingKey.d(k + "_COUNT") }
                guard let count = Int(countStr) else { throw Environment.Errcase.typeIncorrect.d(k) }
                var vs: [Environment.Template] = []
                for i in 0..<count {
                    vs.append(try template.parse(prefix: "\(k)_\(i + 1)", getValue: getValue, extra: values))
                }
                values[key] = vs
            }
        }
        return Self(data: values, extra: extra)
    }
}
