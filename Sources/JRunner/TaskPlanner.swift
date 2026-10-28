import Foundation

/// 一条可执行命令
struct PlannedCommand {
    var executable: String
    var arguments: [String]
    var workingDirectory: String
    var environment: [String: String]
    var displayCommand: String

    /// 人类可读的完整命令描述
    var shellString: String {
        let envPrefix = environment.isEmpty ? "" :
            environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }.joined(separator: " ") + " "
        return envPrefix + ([executable] + arguments.map { TaskPlanner.quoteIfNeeded($0) }).joined(separator: " ")
    }
}

/// 把模块转换为具体的运行/打包命令
enum TaskPlanner {

    /// 生成启动命令
    static func runCommand(project: Project, module: Module, profile: String?, jdk: JDK?) -> PlannedCommand? {
        switch module.tool {
        case .gradle: return gradleCommand(project: project, module: module, task: "bootRun", profile: profile, jdk: jdk)
        case .maven:  return mavenCommand(project: project, module: module, goal: "spring-boot:run", profile: profile, jdk: jdk)
        }
    }

    /// 生成打包命令(jib)
    static func buildCommand(project: Project, module: Module, profile: String?, jdk: JDK?) -> PlannedCommand? {
        switch module.tool {
        case .gradle: return gradleCommand(project: project, module: module, task: "jib", profile: profile, jdk: jdk)
        case .maven:  return mavenCommand(project: project, module: module, goal: "jib:build", profile: profile, jdk: jdk)
        }
    }

    /// 该模块有哪些可用的启动方式
    static func availableRunTasks(for module: Module) -> [String] {
        switch module.tool {
        case .gradle:
            var tasks = ["bootRun"]
            if module.hasJib { tasks.append("jib") }
            return tasks
        case .maven:
            var tasks = ["spring-boot:run"]
            if module.hasJib { tasks.append("jib:build") }
            return tasks
        }
    }

    // MARK: Gradle

    private static func gradleCommand(project: Project, module: Module, task: String, profile: String?, jdk: JDK?) -> PlannedCommand? {
        let root = project.path
        let fm = FileManager.default
        let wrapper = root + "/gradlew"

        let executable: String
        if fm.isExecutableFile(atPath: wrapper) {
            executable = wrapper
        } else if let systemGradle = Shell.which("gradle") {
            executable = systemGradle
        } else if let cached = cachedGradleBinary(preferring: wrapperDeclaredVersion(root: root)) {
            executable = cached
        } else {
            return nil
        }

        var args: [String] = []
        // 非交互输出:纯文本日志,避免 ANSI 进度条污染
        args.append("--console=plain")
        args.append(taskPath(for: module, task: task))

        // Spring Boot 的 profiles 参数
        if let profile, !profile.isEmpty, task == "bootRun" {
            args.append(contentsOf: ["--args=--spring.profiles.active=\(profile)"])
        }

        // 继承用户 shell 环境(数据库地址、Nacos 等变量通常在这里)
        var env = Shell.userEnvironment()
        if let jdk {
            env["JAVA_HOME"] = jdk.home
            env["PATH"] = jdk.home + "/bin:" + Shell.userPath()
        } else {
            env["PATH"] = Shell.userPath()
        }
        // Gradle daemon 内存
        env["GRADLE_OPTS"] = env["GRADLE_OPTS"] ?? "-Xmx2g"

        let isWrapper = fm.isExecutableFile(atPath: wrapper)
        return PlannedCommand(
            executable: executable,
            arguments: args,
            workingDirectory: root,
            environment: env,
            displayCommand: (isWrapper ? "./gradlew " : "gradle ") + taskPath(for: module, task: task)
                + (profile.map { " --args=--spring.profiles.active=\($0)" } ?? "")
        )
    }

    /// 读取 gradle-wrapper.properties 里声明的 gradle 版本
    private static func wrapperDeclaredVersion(root: String) -> [Int]? {
        let p = root + "/gradle/wrapper/gradle-wrapper.properties"
        guard let content = try? String(contentsOfFile: p, encoding: .utf8) else { return nil }
        guard let r = content.range(of: #"gradle-(\d+(?:\.\d+)*)-(?:bin|all)\.zip"#,
                                    options: .regularExpression) else { return nil }
        let token = String(content[r])                       // gradle-8.5-bin.zip
        let verStr = token.dropFirst("gradle-".count).split(separator: "-").first.map(String.init) ?? ""
        let nums = verStr.split(separator: ".").compactMap { Int($0) }
        return nums.isEmpty ? nil : nums
    }

    /// 从 ~/.gradle/wrapper/dists 里找已缓存的 gradle 发行版(离线兜底)。
    /// 优先匹配项目声明的版本,避免版本不兼容导致构建失败。
    private static func cachedGradleBinary(preferring preferred: [Int]?) -> String? {
        let base = FileManager.default.homeDirectoryForCurrentUser.path + "/.gradle/wrapper/dists"
        let fm = FileManager.default
        guard let dists = try? fm.contentsOfDirectory(atPath: base) else { return nil }

        var candidates: [(version: [Int], path: String)] = []

        for dist in dists {
            let distPath = base + "/" + dist
            guard let hashes = try? fm.contentsOfDirectory(atPath: distPath) else { continue }
            for hash in hashes {
                let hashPath = distPath + "/" + hash
                guard let versions = try? fm.contentsOfDirectory(atPath: hashPath) else { continue }
                for v in versions where v.hasPrefix("gradle-") {
                    let bin = hashPath + "/" + v + "/bin/gradle"
                    guard fm.isExecutableFile(atPath: bin) else { continue }
                    let verStr = v.dropFirst("gradle-".count)
                        .split(separator: "-").first.map(String.init) ?? ""
                    let nums = verStr.split(separator: ".").compactMap { Int($0) }
                    guard !nums.isEmpty else { continue }
                    candidates.append((nums, bin))
                }
            }
        }
        guard !candidates.isEmpty else { return nil }

        func compare(_ a: [Int], _ b: [Int]) -> Int {
            for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
            if a.count == b.count { return 0 }
            return a.count < b.count ? -1 : 1
        }

        guard let preferred else {
            // 无声明版本:取最高
            return candidates.max { compare($0.version, $1.version) < 0 }?.path
        }

        // 1. 精确匹配
        if let exact = candidates.first(where: { compare($0.version, preferred) == 0 }) { return exact.path }
        // 2. 高于声明版本中最低的(向后兼容性更好)
        let higher = candidates.filter { compare($0.version, preferred) > 0 }
            .min { compare($0.version, $1.version) < 0 }
        if let higher { return higher.path }
        // 3. 否则取低于声明版本中最高的
        return candidates.filter { compare($0.version, preferred) < 0 }
            .max { compare($0.version, $1.version) < 0 }?.path
    }

    /// 构造 gradle 任务路径。
    /// 根模块(路径为 ":" 或空)直接用 task;子模块用 :path:task
    private static func taskPath(for module: Module, task: String) -> String {
        let p = module.path.trimmingCharacters(in: .whitespaces)
        if p.isEmpty || p == ":" || p == "::" { return task }
        let normalized = p.hasPrefix(":") ? p : ":" + p
        return "\(normalized):\(task)"
    }

    // MARK: Maven

    private static func mavenCommand(project: Project, module: Module, goal: String, profile: String?, jdk: JDK?) -> PlannedCommand? {
        let root = project.path
        let fm = FileManager.default
        let wrapper = root + "/mvnw"

        let executable: String
        if fm.isExecutableFile(atPath: wrapper) {
            executable = wrapper
        } else if let systemMvn = Shell.which("mvn") {
            executable = systemMvn
        } else {
            return nil
        }

        var args: [String] = ["-B"]     // batch mode: 纯文本输出,无 ANSI 进度条
        if module.path.isEmpty || module.path == "." || module.path == ":" {
            args.append(goal)
        } else {
            args.append(contentsOf: ["-pl", module.path, goal])
        }
        if let profile, !profile.isEmpty {
            args.append(contentsOf: ["-P", profile])
        }

        var env = Shell.userEnvironment()
        if let jdk {
            env["JAVA_HOME"] = jdk.home
            env["PATH"] = jdk.home + "/bin:" + Shell.userPath()
        } else {
            env["PATH"] = Shell.userPath()
        }

        return PlannedCommand(
            executable: executable,
            arguments: args,
            workingDirectory: root,
            environment: env,
            displayCommand: (fm.isExecutableFile(atPath: wrapper) ? "./mvnw " : "mvn ") + args.joined(separator: " ")
        )
    }

    static func quoteIfNeeded(_ s: String) -> String {
        if s.contains(where: { $0 == " " || $0 == "\"" || $0 == "'" }) {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return s
    }
}
