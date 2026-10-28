import Foundation

// MARK: - Model

/// 构建工具类型
enum BuildTool: String, Codable, CaseIterable {
    case gradle
    case maven

    var displayName: String {
        switch self {
        case .gradle: return "Gradle"
        case .maven: return "Maven"
        }
    }
}

/// 可运行模块（一个 Gradle 子项目 / Maven module）
struct Module: Identifiable, Hashable, Codable {
    var id: String { path }
    /// 相对项目根的路径,例如 ":community-portal"
    var path: String
    /// 目录名,例如 "community-portal"
    var name: String
    /// 绝对路径
    var absolutePath: String
    /// 语言: kotlin / java / groovy
    var language: String
    /// 是否包含 Spring Boot 启动类
    var isSpringBoot: Bool
    /// 是否检测到 jib 插件
    var hasJib: Bool
    /// 构建工具
    var tool: BuildTool
    /// 该模块声明的 JDK 需求(如 toolchain 17)
    var javaVersion: Int?
    /// 可用的 Spring Profile(来自 application-*.yaml)
    var availableProfiles: [String] = []
    /// 配置里声明的默认 profile
    var defaultProfile: String?

    /// 展示用路径:去掉 Gradle 的前导冒号,根模块回退为项目名
    var displayPath: String {
        let trimmed = path.hasPrefix(":")
            ? String(path.dropFirst())
            : path
        return trimmed.isEmpty ? name : trimmed
    }
}

enum ProjectLanguage: String, Codable {
    case kotlin = "Kotlin"
    case java = "Java"
    case mixed = "Java/Kotlin"
}

/// 一个项目根目录
struct Project: Identifiable, Hashable, Codable {
    var id: String { path }
    var name: String
    var path: String
    var tool: BuildTool
    var language: ProjectLanguage
    var modules: [Module]
    /// 扫描到的 JDK 需求集合(取众数)
    var requiredJava: Int?
    /// 是否有 gradle wrapper
    var hasWrapper: Bool
}

// MARK: - Scanner

enum ProjectScanner {

    /// 扫描一个目录,返回项目信息。目录不是项目则返回 nil。
    static func scan(at path: String) -> Project? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let settingsGradle = findFile(path, names: ["settings.gradle", "settings.gradle.kts"])
        let pom = findFile(path, names: ["pom.xml"])
        let buildGradle = findFile(path, names: ["build.gradle", "build.gradle.kts"])

        // 没有 settings/pom 但有 build.gradle 也算单模块 gradle 项目
        let tool: BuildTool?
        if settingsGradle != nil || buildGradle != nil {
            tool = .gradle
        } else if pom != nil {
            tool = .maven
        } else {
            tool = nil
        }
        guard let tool else { return nil }

        var modules: [Module] = []
        switch tool {
        case .gradle: modules = scanGradleModules(root: path, settingsFile: settingsGradle)
        case .maven:  modules = scanMavenModules(root: path)
        }

        // 空模块列表时,把根目录本身当作模块
        if modules.isEmpty {
            if let m = makeModule(dir: path, gradlePath: ":", name: (path as NSString).lastPathComponent, tool: tool) {
                modules = [m]
            }
        }
        guard !modules.isEmpty else { return nil }

        let lang = detectLanguage(root: path, modules: modules)
        let javaVer = detectJavaVersion(root: path, modules: modules)
        let hasWrapper = fm.fileExists(atPath: path + "/gradlew")

        return Project(
            name: (path as NSString).lastPathComponent,
            path: path,
            tool: tool,
            language: lang,
            modules: modules,
            requiredJava: javaVer,
            hasWrapper: hasWrapper
        )
    }

    // MARK: Gradle

    private static func scanGradleModules(root: String, settingsFile: String?) -> [Module] {
        var modulePaths: [String] = []

        if let settingsFile {
            let content = (try? String(contentsOfFile: settingsFile, encoding: .utf8)) ?? ""
            modulePaths = parseGradleIncludes(content)
        }

        // 没有 include 或解析失败时,扫描一级子目录找 build.gradle
        if modulePaths.isEmpty {
            let fm = FileManager.default
            let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
            for e in entries {
                if e.hasPrefix(".") { continue }
                let sub = root + "/" + e
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue else { continue }
                if fm.fileExists(atPath: sub + "/build.gradle") || fm.fileExists(atPath: sub + "/build.gradle.kts") {
                    modulePaths.append(":\(e)")
                }
            }
        }

        var modules: [Module] = []
        for mp in modulePaths {
            let rel = String(mp.dropFirst())            // 去掉前导 ':'
            let dir = rel.isEmpty ? root : root + "/" + rel
            guard let m = makeModule(dir: dir, gradlePath: mp, name: (rel as NSString).lastPathComponent, tool: .gradle) else { continue }
            modules.append(m)
        }
        return modules
    }

    /// 从 settings.gradle 中提取 include(...) 的模块路径
    /// 逐行解析,支持单行与跨行 include 块
    private static func parseGradleIncludes(_ content: String) -> [String] {
        var result: [String] = []
        var buffer: String?
        var depth = 0

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let codeLine = stripComment(line)

            if buffer == nil {
                guard codeLine.hasPrefix("include") else { continue }
                // 确认是 include 语句而非 includedBuild 之类的标识符
                let rest = codeLine.dropFirst("include".count)
                let isStatement = rest.isEmpty
                    || rest.hasPrefix("(")
                    || rest.hasPrefix(" ")
                    || rest.hasPrefix("'")
                    || rest.hasPrefix("\"")
                guard isStatement else { continue }
                buffer = codeLine
            } else {
                buffer! += "\n" + codeLine
            }

            guard let stmt = buffer else { continue }
            depth = stmt.filter { $0 == "(" }.count - stmt.filter { $0 == ")" }.count
            if depth > 0 { continue }        // 括号未闭合,继续累积

            buffer = nil
            for s in quotedStrings(stmt) {
                let normalized = s.hasPrefix(":") ? s : ":" + s
                if !result.contains(normalized) { result.append(normalized) }
            }
        }

        return result
    }

    /// 去掉行内注释(# 或 //),但保留引号内的内容
    private static func stripComment(_ line: String) -> String {
        var result = ""
        var inQuote = false
        var quoteChar: Character = "'"
        var prev: Character = " "

        for ch in line {
            if inQuote {
                result.append(ch)
                if ch == quoteChar { inQuote = false }
            } else {
                if ch == "'" || ch == "\"" {
                    inQuote = true
                    quoteChar = ch
                    result.append(ch)
                } else if ch == "#" {
                    break
                } else if ch == "/" && prev == "/" {
                    // 回退已写入的第二个 '/'
                    result.removeLast()
                    break
                } else {
                    result.append(ch)
                }
            }
            prev = ch
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 提取字符串中所有被单/双引号包裹的内容
    private static func quotedStrings(_ s: String) -> [String] {
        var out: [String] = []
        var inQuote = false
        var cur = ""
        var quoteChar: Character = "'"
        for ch in s {
            if !inQuote {
                if ch == "'" || ch == "\"" {
                    inQuote = true
                    quoteChar = ch
                    cur = ""
                }
            } else {
                if ch == quoteChar {
                    out.append(cur)
                    inQuote = false
                    cur = ""
                } else {
                    cur.append(ch)
                }
            }
        }
        return out
    }

    // MARK: Maven

    private static func scanMavenModules(root: String) -> [Module] {
        var modulePaths: [String] = []
        if let pom = findFile(root, names: ["pom.xml"]) {
            let content = (try? String(contentsOfFile: pom, encoding: .utf8)) ?? ""
            modulePaths = parseMavenModules(content)
        }
        var modules: [Module] = []
        for mp in modulePaths {
            let dir = mp.isEmpty ? root : root + "/" + mp
            guard let m = makeModule(dir: dir, gradlePath: mp, name: (mp as NSString).lastPathComponent, tool: .maven) else { continue }
            modules.append(m)
        }
        return modules
    }

    /// 从 pom.xml 的 <modules> 中提取
    private static func parseMavenModules(_ content: String) -> [String] {
        var out: [String] = []
        guard let range = content.range(of: "<modules>", options: .caseInsensitive) else { return [] }
        let tail = String(content[range.upperBound...])
        guard let endRange = tail.range(of: "</modules>", options: .caseInsensitive) else { return [] }
        let block = String(tail[tail.startIndex..<endRange.lowerBound])
        let pattern = #"<module>\s*([^<]+?)\s*</module>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = NSRange(location: 0, length: (block as NSString).length)
        regex.enumerateMatches(in: block, options: [], range: ns) { m, _, _ in
            guard let m, m.numberOfRanges >= 2 else { return }
            out.append((block as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces))
        }
        return out
    }

    // MARK: Module detection

    private static func makeModule(dir: String, gradlePath: String, name: String, tool: BuildTool) -> Module? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }

        let hasBuildFile = tool == .gradle
            ? (fm.fileExists(atPath: dir + "/build.gradle") || fm.fileExists(atPath: dir + "/build.gradle.kts"))
            : fm.fileExists(atPath: dir + "/pom.xml")

        let sources = dir + "/src"
        let lang = detectLanguageInDir(sources)
        let spring = detectSpringBoot(sources)
        let jib = detectJib(dir)
        let javaVer = detectModuleJavaVersion(dir)

        // 既没有构建文件也没有源码的目录跳过
        if !hasBuildFile && lang == nil { return nil }

        return Module(
            path: gradlePath,
            name: name.isEmpty ? (dir as NSString).lastPathComponent : name,
            absolutePath: dir,
            language: lang ?? "Java",
            isSpringBoot: spring,
            hasJib: jib,
            tool: tool,
            javaVersion: javaVer,
            availableProfiles: detectProfiles(dir),
            defaultProfile: detectDefaultProfile(dir)
        )
    }

    /// 扫描 src/main/resources 下的 application-*.yaml,列出可用 profile
    private static func detectProfiles(_ dir: String) -> [String] {
        let resDir = dir + "/src/main/resources"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: resDir) else { return [] }

        var profiles: [String] = []
        for f in files {
            guard f.hasPrefix("application-") else { continue }
            for ext in [".yaml", ".yml", ".properties"] where f.hasSuffix(ext) {
                let name = String(f.dropFirst("application-".count).dropLast(ext.count))
                if !name.isEmpty, !profiles.contains(name) { profiles.append(name) }
            }
        }
        // dev 排前面,便于本地开发
        return profiles.sorted { a, b in
            if a == "dev" { return true }
            if b == "dev" { return false }
            return a < b
        }
    }

    /// 从 application.yaml 读取 spring.profiles.active(支持 ${ENV:默认值})
    private static func detectDefaultProfile(_ dir: String) -> String? {
        let resDir = dir + "/src/main/resources"
        for name in ["application.yaml", "application.yml", "application.properties"] {
            let p = resDir + "/" + name
            guard let content = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
            guard let r = content.range(of: #"active\s*:\s*([^\n\r]+)"#, options: .regularExpression) else { continue }
            var value = String(content[r])
            if let colon = value.firstIndex(of: ":") {
                value = String(value[value.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            // 去掉行尾注释,如 "prod #dev, prod"
            if let hash = value.firstIndex(of: "#") {
                value = String(value[value.startIndex..<hash])
            }
            // ${SPRING_PROFILES_ACTIVE:prod} → prod
            if value.contains("${") {
                if let lastColon = value.lastIndex(of: ":") {
                    value = String(value[value.index(after: lastColon)...])
                }
                value = value.replacingOccurrences(of: "}", with: "")
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func detectLanguageInDir(_ dir: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
        let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        var kt = 0, java = 0
        for e in entries {
            if e == "main" || e == "test" {
                let sub = dir + "/" + e
                let subEntries = (try? fm.contentsOfDirectory(atPath: sub)) ?? []
                for se in subEntries {
                    if se == "java" { java += 1 }
                    if se == "kotlin" { kt += 1 }
                }
            }
        }
        if kt > 0 && java > 0 { return "Kotlin" }
        if kt > 0 { return "Kotlin" }
        if java > 0 { return "Java" }
        return nil
    }

    private static func detectSpringBoot(_ srcDir: String) -> Bool {
        let fm = FileManager.default
        guard let files = try? fm.subpathsOfDirectory(atPath: srcDir) else { return false }

        // 只扫源码文件;启动类通常叫 *Application,优先检查它,避免大项目全量读取
        var sources = files.filter { $0.hasSuffix(".kt") || $0.hasSuffix(".java") }
        sources.sort { a, b in
            let aApp = (a as NSString).lastPathComponent.contains("Application")
            let bApp = (b as NSString).lastPathComponent.contains("Application")
            if aApp != bApp { return aApp }
            return a < b
        }
        if sources.count > 400 { sources = Array(sources.prefix(400)) }

        for f in sources {
            guard let content = try? String(contentsOfFile: srcDir + "/" + f, encoding: .utf8) else { continue }
            if content.contains("@SpringBootApplication") { return true }
            if content.contains("SpringApplication.run") { return true }
        }
        return false
    }

    private static func detectJib(_ dir: String) -> Bool {
        for name in ["build.gradle", "build.gradle.kts", "pom.xml"] {
            let p = dir + "/" + name
            guard let content = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
            if content.contains("com.google.cloud.tools.jib") { return true }
            if content.contains("jib-maven-plugin") { return true }
            if content.range(of: #"\bjib\s*\{"#, options: .regularExpression) != nil { return true }
            if content.range(of: #"\bid\s*\(?\s*['"]jib['"]"#, options: .regularExpression) != nil { return true }
        }
        return false
    }

    private static func detectModuleJavaVersion(_ dir: String) -> Int? {
        for name in ["build.gradle", "build.gradle.kts", "pom.xml"] {
            let p = dir + "/" + name
            guard let content = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
            // toolchain / sourceCompatibility
            let patterns = [
                #"languageVersion\.set\(JavaLanguageVersion\.of\((\d+)\)\)"#,
                #"sourceCompatibility\s*=\s*JavaVersion\.VERSION_(\d+)"#,
                #"targetCompatibility\s*=\s*JavaVersion\.VERSION_(\d+)"#,
                #"<maven\.compiler\.source>\s*(\d+)"#,
                #"<java\.version>\s*(\d+)"#
            ]
            for pat in patterns {
                if let r = firstMatch(content, pattern: pat), let v = Int(r) { return v }
            }
        }
        return nil
    }

    private static func detectJavaVersion(root: String, modules: [Module]) -> Int? {
        let counts = Dictionary(grouping: modules.compactMap { $0.javaVersion }, by: { $0 })
        return counts.max { a, b in a.value.count < b.value.count }?.key
    }

    private static func detectLanguage(root: String, modules: [Module]) -> ProjectLanguage {
        let hasKotlin = modules.contains { $0.language == "Kotlin" }
        let hasJava = modules.contains { $0.language == "Java" }
        if hasKotlin && hasJava { return .mixed }
        if hasKotlin { return .kotlin }
        return .java
    }

    // MARK: Helpers

    private static func findFile(_ dir: String, names: [String]) -> String? {
        for n in names {
            let p = dir + "/" + n
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = NSRange(location: 0, length: (text as NSString).length)
        guard let m = regex.firstMatch(in: text, options: [], range: ns), m.numberOfRanges >= 2 else { return nil }
        return (text as NSString).substring(with: m.range(at: 1))
    }
}
