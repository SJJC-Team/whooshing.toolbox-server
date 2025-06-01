import Vapor
import ErrorHandle

extension Environment.Config: Environment.Template {
    internal static var envs: [String: Environment.Types] { [ "name": .string, "port": .int, "#domain": .string, "db": .dataTemplate(Environment.DB.self), "manager_url": .url ] }
    internal init(data: [String : Any]) {
        self.name = data["name"] as! String
        self.port = data["port"] as! Int
        self.databases = data["db"] as! [Environment.DB]
        self.domain = data["domain"] as? String
        self.managerUrl = data["manager_url"] as! URL
    }
}

extension Environment.DB: Environment.Template {
    internal static var envs: [String: Environment.Types] { [ "name": .string, "port": .int, "user": .string, "password": .string ] }
    internal init(data: [String : Any]) {
        self.name = data["name"] as! String
        self.port = data["port"] as! Int
        self.user = data["user"] as! String
        self.password = data["password"] as! String
        self.unsafeTestOnlyHost = nil
        self.connectionPoolTimeout = .seconds(10)
        self.maxConnectionsPerEventLoop = 1
        self.sqlLogLevel = .info
    }
}

extension Environment {
    static func get(with prefix: String) throws -> Config { try .parse(prefix: prefix) }
    
    enum Types {
        case string
        case int
        case stringArr
        case intArr
        case url
        case uri
        case uuid
        case dataTemplate(Template.Type)
    }

    protocol Template {
        static var envs: [String: Types] { get }
        init(data: [String: Any])
        init()
    }

    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.env.err" }
        case parseFailed = "环境变量解析失败"
        case typeIncorrect = "环境变量配置类型不匹配"
        case missingKey = "环境变量配置字段缺失"
    }
}

extension Environment.Template {
    static func parse(prefix: String?, getValue: @escaping ((String) -> String?) = { Environment.get($0) }) throws -> Self {
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
            case .string, .int, .intArr, .url, .uri, .uuid, .stringArr: guard let vv = getValue(k) else { throw Environment.Err.missingKey.d(k, 10000) }; value = vv
                default: value = nil
            }
            
            switch v {
                case .string: values[key] = value
                case .int: guard let v = Int(value) else { throw Environment.Err.typeIncorrect.d(k, 10003) }; values[key] = v
                case .stringArr: values[key] = value.split(separator: ",").map { String($0) }
                case .url: guard let v = URL(string: value) else { throw Environment.Err.typeIncorrect.d(k, 10004) }; values[key] = v
                case .uri: values[key] = URI(string: value)
                case .uuid: guard let v = UUID(uuidString: value) else { throw Environment.Err.typeIncorrect.d(k, 10096) }; values[key] = v
                case .intArr: values[key] = try value.split(separator: ",").map { guard let v = Int($0) else { throw Environment.Err.typeIncorrect.d(k) }; return v }
                case .dataTemplate(let template):
                    guard let countStr = getValue(k + "_COUNT") else { throw Environment.Err.missingKey.d(k + "_COUNT", 10001) }
                    guard let count = Int(countStr) else { throw Environment.Err.typeIncorrect.d(k, 10002) }
                    var vs: [Environment.Template] = []
                    for i in 0..<count {
                        vs.append(try template.parse(prefix: "\(k)_\(i + 1)", getValue: getValue))
                    }
                    values[key] = vs
            }
        }
        return Self(data: values)
    }
}
