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
        origin["name"] = .string()
        origin["port"] = .int()
        origin["hostname"] = .string()
        origin["domain"] = .string(optional: true)
        origin["manager_url"] = .url()
        origin["db_services"] = .array(.dataTemplate(Environment.DBService.self))
        origin["log_file_urls"] = .array(.url())
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
        self.logFileUrls = data["log_file_urls"] as! [URL]
        self.driverKeys = driverKeys
        for key in driverKeys {
            self.storage = key.apply(on: storage, value: data[key.label])
        }
    }
}

extension Environment.DBService: Environment.Template {
    @inlinable
    public static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["name"] = .string()
        origin["port"] = .int()
        origin["dbs"] = .array(.dataTemplate(Environment.DB.self))
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
        origin["name"] = .string()
        origin["user"] = .string()
        origin["password"] = .string()
        origin["file_storage_key"] = .base64Data(optional: true)
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
    
    public indirect enum Types: Sendable {
        case string(optional: Bool = false)
        case int(any (FixedWidthInteger & Sendable).Type = Int.self, optional: Bool = false)
        case base64String(optional: Bool = false)
        case base64Data(optional: Bool = false)
        case url(optional: Bool = false)
        case uri(optional: Bool = false)
        case uuid(optional: Bool = false)
        case dataTemplate(Template.Type, optional: Bool = false)
        case array(Self, optional: Bool = false)
        
        public var isOptional: Bool {
            switch self {
            case .string(let optional): optional
            case .int(_, let optional): optional
            case .base64String(let optional): optional
            case .base64Data(let optional): optional
            case .url(let optional): optional
            case .uri(let optional): optional
            case .uuid(let optional): optional
            case .dataTemplate(_, let optional): optional
            case .array(_, let optional): optional
            }
        }
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
        for (key, v) in Self.envs(driverKeys: driverKeys) {
            let k = prefix == nil ? key : "\(prefix!)_\(key.uppercased())"
            
            values[key] = try castValue(
                prefix: prefix,
                key: k,
                value: v,
                driverKeys: driverKeys,
                getValue: getValue,
                extra: values,
                nullable: nullable
            )
        }
        return Self(data: values, driverKeys: driverKeys, extra: extra)
    }
    
    @inlinable
    static func castValue(
        prefix: String?,
        key k: String,
        value v: Environment.Types,
        driverKeys: [any Environment.DriverKey.Type],
        getValue: @escaping ((String) -> String?),
        extra: [String: Any] = [:],
        nullable: Bool
    ) throws(Environment.Errcase.ErrType) -> Any? {
        let value: String!
        let optional = v.isOptional
        switch v {
        case .string, .int, .url, .uri, .uuid, .base64Data, .base64String:
            guard let vv = getValue(k) else {
                if optional {
                    return nil
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
            return value
            
        case .int(let type, _):
            guard let v = type.init(value) else { throw Environment.Errcase.typeIncorrect.d(k) }
            return v
            
        case .base64String:
            return Base64String(value)
            
        case .base64Data:
            return try required(throws: Environment.Errcase.parseFailed, k) {
                try Base64String(value).dataRes.get()
            }
            
        case .uri:
            return URI(string: value)
            
        case .url:
            guard let v = URL(string: value) else { throw Environment.Errcase.typeIncorrect.d(k) }
            return v
            
        case .uuid:
            guard let v = UUID(uuidString: value) else { throw Environment.Errcase.typeIncorrect.d(k) }
            return v
            
        case .dataTemplate(let template, _):
            if optional {
                return try template.nullableParse(prefix: k, driverKeys: driverKeys, getValue: getValue, extra: extra, nullable: true)
            } else {
                if nullable {
                    guard let res = try template.nullableParse(prefix: k, driverKeys: driverKeys, getValue: getValue, extra: extra, nullable: true) else {
                        return nil
                    }
                    return res
                } else {
                    return try template.parse(prefix: k, driverKeys: driverKeys, getValue: getValue, extra: extra)
                }
            }
            
        case .array(let value, _):
            guard let countStr = getValue(k + "_COUNT") else {
                if optional {
                    return nil
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
                    return nil
                } else {
                    if nullable {
                        return nil
                    } else {
                        throw Environment.Errcase.typeIncorrect.d(k)
                    }
                }
            }
            
            var vs: [Any?] = []
            for i in 0..<count {
                if let item = try castValue(
                    prefix: prefix,
                    key: "\(k)_\(i + 1)",
                    value: value,
                    driverKeys: driverKeys,
                    getValue: getValue,
                    extra: extra,
                    nullable: false
                ) {
                    vs.append(item)
                } else {
                    if value.isOptional {
                        vs.append(nil)
                    } else {
                        if nullable {
                            return nil
                        } else {
                            throw Environment.Errcase.missingKey.d("\(k)_\(i + 1)")
                        }
                    }
                }
            }
            return vs
        }
    }
}
