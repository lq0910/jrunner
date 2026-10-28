import Foundation

/// 单个模块的运行配置
struct ModuleConfig: Codable, Hashable {
    /// 启动时使用的 Spring profile
    var profile: String?
    /// 覆盖 JDK 版本
    var javaVersion: Int?
    /// 额外环境变量
    var envVars: [String: String] = [:]
    /// 额外 gradle 参数
    var extraArgs: [String] = []
}

/// 全局配置
struct AppConfig: Codable {
    var projects: [String: [String: ModuleConfig]] = [:]   // projectPath -> modulePath -> config
    var lastOpenedProject: String?
    var logLevelFilter: String = "info"
    var maxLogLines: Int = 20000

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: Self.configURL),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return cfg
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
        try? data.write(to: Self.configURL)
    }

    static var configDir: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("JRunner", isDirectory: true)
        return base
    }

    static var configURL: URL {
        configDir.appendingPathComponent("config.json")
    }

    func config(for project: String, module: String) -> ModuleConfig {
        projects[project]?[module] ?? ModuleConfig()
    }

    mutating func setConfig(_ cfg: ModuleConfig, for project: String, module: String) {
        projects[project, default: [:]][module] = cfg
    }
}
