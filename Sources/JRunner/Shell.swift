import Foundation

/// Shell 执行结果
struct ShellResult {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
    var combined: String { standardOutput + standardError }
}

/// 一次性同步执行 shell 命令
enum Shell {

    @discardableResult
    static func run(_ launchPath: String, args: [String], cwd: String? = nil, env: [String: String]? = nil) -> ShellResult? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if let env { p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new } }

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        do { try p.run() } catch { return nil }

        // 必须并发读取,否则管道缓冲区满会死锁
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "shell.read", attributes: .concurrent)

        queue.async(group: group) { outData = out.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errData = err.fileHandleForReading.readDataToEndOfFile() }

        p.waitUntilExit()
        group.wait()

        return ShellResult(
            exitCode: p.terminationStatus,
            standardOutput: String(data: outData, encoding: .utf8) ?? "",
            standardError: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// 查找 PATH 中的可执行文件
    static func which(_ name: String) -> String? {
        for dir in userPath().split(separator: ":") {
            let full = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    // MARK: - 用户环境变量

    private static var cachedEnv: [String: String]?
    private static let envLock = NSLock()

    /// 读取 login shell 的完整环境变量。
    /// GUI 应用不继承用户在 .zshrc 里 export 的变量(数据库地址、Nacos 地址等),
    /// 这里通过 login shell 取回来,让行为与终端里执行一致。
    static func userEnvironment() -> [String: String] {
        envLock.lock()
        defer { envLock.unlock() }
        if let cachedEnv { return cachedEnv }

        var result: [String: String] = [:]
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let r = run(shell, args: ["-lc", "env"], cwd: nil) {
            for line in r.standardOutput.components(separatedBy: .newlines) {
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[line.startIndex..<eq])
                let value = String(line[line.index(after: eq)...])
                guard isValidEnvKey(key) else { continue }
                result[key] = value
            }
        }

        // 这些变量由我们自己控制,不继承
        for k in ["PWD", "OLDPWD", "SHLVL", "_", "PS1", "TERM", "SHELL", "PATH", "JAVA_HOME"] {
            result.removeValue(forKey: k)
        }

        cachedEnv = result
        return result
    }

    private static func isValidEnvKey(_ key: String) -> Bool {
        guard let first = key.first, first.isLetter || first == "_" else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - 用户 PATH

    private static var cachedPath: String?
    private static let pathLock = NSLock()

    /// 获取用户真实 PATH。
    /// GUI 应用默认只有 /usr/bin:/bin:/usr/sbin:/sbin,
    /// 这里通过 login shell 读取用户在 .zshrc 里配置的 PATH。
    static func userPath() -> String {
        pathLock.lock()
        defer { pathLock.unlock() }
        if let cachedPath { return cachedPath }

        var parts: [String] = []

        // 1. login shell 的 PATH
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if let r = run(shell, args: ["-lc", "echo -n $PATH"], cwd: nil) {
            // .zshrc 可能有其他输出,取最后一个像 PATH 的行
            let candidates = r.standardOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.contains("/") }
            if let last = candidates.last {
                parts = last.split(separator: ":").map(String.init)
            }
        }

        // 2. 常见安装位置兜底
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extras = [
            home + "/.sdkman/candidates/gradle/current/bin",
            home + "/.sdkman/candidates/maven/current/bin",
            home + "/.sdkman/candidates/java/current/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        for e in extras where !parts.contains(e) {
            if FileManager.default.fileExists(atPath: e) { parts.append(e) }
        }

        let result = parts.joined(separator: ":")
        cachedPath = result
        return result
    }
}
