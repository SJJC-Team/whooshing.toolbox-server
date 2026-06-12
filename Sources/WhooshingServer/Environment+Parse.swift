import Vapor
import FluentKit
import ErrorHandle
import DataConvertable
import Collections
import OrderedCollections
import SystemPackage
import AnyCodable
import Cryptos

extension Environment.Config: Environment.Template {
    @inlinable
    public static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["name"] = .string
        origin["port"] = .int()
        origin["hostname"] = .string
        origin["#domain"] = .string
        origin["manager_url"] = .url
        origin["db_services"] = .dataTemplates(Environment.DBService.self)
    }
    
    @inlinable
    public static func with(driverKeys: [any Environment.DriverKey.Type], dic origin: inout OrderedDictionary<String, Environment.Types>) {
        for key in driverKeys {
            origin[key.envName] = key.valueType
        }
    }
    
    @inlinable
    public init(data: [String: Any], driverKeys: [any Environment.DriverKey.Type], extra: [String: Any]) {
        self.name = data["name"] as! String
        self.port = data["port"] as! Int
        self.hostname = data["hostname"] as! String
        self.dbServices = data["db_services"] as! [Environment.DBService]
        self.domain = data["domain"] as? String
        self.managerUrl = data["manager_url"] as! URL
        self.driverKeys = driverKeys
        for key in driverKeys {
            self.storage = key.apply(on: storage, value: data[key.label]!)
        }
    }
}

extension Environment.DBService: Environment.Template {
    @inlinable
    public static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["name"] = .string
        origin["port"] = .int()
        origin["dbs"] = .dataTemplates(Environment.DB.self)
    }
    
    @inlinable
    public init(data: [String : Any], driverKeys: [any Environment.DriverKey.Type], extra: [String: Any]) {
        self.id = .init(string: data["name"] as! String)
        self.port = data["port"] as! Int
        self.dbs = data["dbs"] as! [Environment.DB]
    }
}

extension Environment.DB: Environment.Template {
    @inlinable
    public static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["name"] = .string
        origin["user"] = .string
        origin["password"] = .string
        origin["#file_storage_key"] = .base64Data
    }
    
    @inlinable
    public init(data: [String : Any], driverKeys: [any Environment.DriverKey.Type], extra: [String : Any]) {
        let keyData = data["file_storage_key"]
        self = Self.init(
            dbServiceId: .init(string: extra["name"] as! String),
            port: extra["port"] as! Int,
            parameter: .init(
                name: data["name"] as! String,
                user: data["user"] as! String,
                password: data["password"] as! String,
                testingHost: nil,
                fileStorageKey: keyData == nil ? nil : .new(data: keyData as! Data)
            )
        )
    }
}

extension Environment {
    @inlinable
    static func get(with prefix: String, driverKeys: [any DriverKey.Type] = []) throws(Errcase.ErrType) -> Config { try .parse(prefix: prefix, driverKeys: driverKeys) }
    
    public enum Types: Sendable {
        case string
        case stringArr
        case int(any (FixedWidthInteger & Sendable).Type = Int.self)
        case intArr(any (FixedWidthInteger & Sendable).Type = Int.self)
        case base64String
        case base64Data
        case url
        case uri
        case uuid
        case dataTemplate(Template.Type)
        case dataTemplates(Template.Type)
    }

    public protocol Template: Sendable {
        static func envs(driverKeys: [any Environment.DriverKey.Type]) -> OrderedDictionary<String, Environment.Types>
        static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>)
        static func with(driverKeys: [any DriverKey.Type], dic origin: inout OrderedDictionary<String, Environment.Types>)
        init(data: [String: Any], driverKeys: [any DriverKey.Type], extra: [String: Any])
        init()
    }

    @frozen
    public enum Errcase: String, ErrList {
        case parseFailed = "环境变量解析失败"
        case typeIncorrect = "环境变量配置类型不匹配"
        case missingKey = "环境变量配置字段缺失"
        case internalFailed = "内部错误"
    }
}

public extension Environment.Template {
    @inlinable
    static func envs(driverKeys: [any Environment.DriverKey.Type]) -> OrderedDictionary<String, Environment.Types> {
        var res = OrderedDictionary<String, Environment.Types>()
        withEnv(dic: &res)
        with(driverKeys: driverKeys, dic: &res)
        return res
    }
    
    @inlinable
    static func with(driverKeys: [any Environment.DriverKey.Type], dic origin: inout OrderedDictionary<String, Environment.Types>) {}
}

extension Environment.Template {
    @inlinable
    static func parse(
        prefix: String?,
        driverKeys: [any Environment.DriverKey.Type] = [],
        getValue: @escaping ((String) -> String?) = { Environment.get($0) },
        extra: [String: Any] = [:]
    ) throws(Environment.Errcase.ErrType) -> Self {
        guard let res = try nullableParse(
            prefix: prefix,
            driverKeys: driverKeys,
            getValue: getValue,
            extra: extra,
            nullable: false
        ) else {
            throw Environment.Errcase.internalFailed.d(prefix ?? "<<No prefix>>")
        }
        return res
    }
    
    @inlinable
    static func nullableParse(
        prefix: String?,
        driverKeys: [any Environment.DriverKey.Type],
        getValue: @escaping ((String) -> String?) = { Environment.get($0) },
        extra: [String: Any] = [:],
        nullable: Bool
    ) throws(Environment.Errcase.ErrType) -> Self? {
        var values: [String: Any] = [:]
        for (var key, v) in Self.envs(driverKeys: driverKeys) {
            
            let optional = key.hasPrefix("#")
            
            if optional { key = String(key.dropFirst()) }
            let k = prefix == nil ? key : "\(prefix!)_\(key.uppercased())"
            let value: String!
            
            switch v {
            case .string, .int, .intArr, .url, .uri, .uuid, .stringArr, .base64Data, .base64String:
                guard let vv = getValue(k) else {
                    if optional {
                        continue
                    } else {
                        if nullable {
                            return nil
                        } else {
                            throw Environment.Errcase.missingKey.d(k)
                        }
                    }
                }
                value = vv
            default:
                value = nil
            }
            
            switch v {
            case .string:
                values[key] = value
                
            case .stringArr:
                values[key] = value.split(separator: ",").map { String($0) }
                
            case .int(let type):
                guard let v = type.init(value) else { throw Environment.Errcase.typeIncorrect.d(k) }
                values[key] = v
                
            case .intArr(let type):
                values[key] = try value.split(separator: ",").map { v throws(Environment.Errcase.ErrType) in
                    guard let v = type.init(v) else {
                        throw Environment.Errcase.typeIncorrect.d(k)
                    }
                    return v
                }
                
            case .base64String:
                values[key] = Base64String(value)
                
            case .base64Data:
                values[key] = try required(throws: Environment.Errcase.parseFailed, k) {
                    try Base64String(value).dataRes.get()
                }
                
            case .uri:
                values[key] = URI(string: value)
                
            case .url:
                guard let v = URL(string: value) else { throw Environment.Errcase.typeIncorrect.d(k) }
                values[key] = v
                
            case .uuid:
                guard let v = UUID(uuidString: value) else { throw Environment.Errcase.typeIncorrect.d(k) }
                values[key] = v
                
            case .dataTemplate(let template):
                if optional {
                    values[key] = try template.nullableParse(prefix: k, driverKeys: driverKeys, getValue: getValue, extra: values, nullable: true)
                } else {
                    if nullable {
                        guard let res = try template.nullableParse(prefix: k, driverKeys: driverKeys, getValue: getValue, extra: values, nullable: true) else {
                            return nil
                        }
                        values[key] = res
                    } else {
                        values[key] = try template.parse(prefix: k, driverKeys: driverKeys, getValue: getValue, extra: values)
                    }
                }
                
            case .dataTemplates(let template):
                guard let countStr = getValue(k + "_COUNT") else {
                    if optional {
                        continue
                    } else {
                        if nullable {
                            return nil
                        } else {
                            throw Environment.Errcase.missingKey.d(k + "_COUNT")
                        }
                    }
                }
                
                guard let count = Int(countStr) else {
                    if optional {
                        continue
                    } else {
                        if nullable {
                            return nil
                        } else {
                            throw Environment.Errcase.typeIncorrect.d(k)
                        }
                    }
                }
                
                var vs: [Environment.Template] = []
                for i in 0..<count {
                    vs.append(try template.parse(prefix: "\(k)_\(i + 1)", driverKeys: driverKeys, getValue: getValue, extra: values))
                }
                values[key] = vs
            }
        }
        return Self(data: values, driverKeys: driverKeys, extra: extra)
    }
}
