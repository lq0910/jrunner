import Foundation

/// 已安装的 JDK
struct JDK: Identifiable, Hashable {
    var id: String { home }
    var version: Int          // 主版本号,如 17
    var fullVersion: String   // 如 "17.0.15"
    var vendor: String        // 如 "Amazon.com Inc."
    var home: String          // JAVA_HOME 路径
    var isCurrent: Bool       // 是否为系统默认
}

/// 解析本机安装的 JDK
enum JDKResolver {

    private static var cache: [JDK]?
    private static let lock = NSLock()

    /// 读取 `/usr/libexec/java_home -V` 的输出(带缓存)
    static func installedJDKs(forceRefresh: Bool = false) -> [JDK] {
        lock.lock()
        defer { lock.unlock() }

        if !forceRefresh, let cache { return cache }
        let list = detectJDKs()
        cache = list
        return list
    }

    static func invalidateCache() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    private static func detectJDKs() -> [JDK] {
        guard let result = Shell.run("/usr/libexec/java_home", args: ["-V"], cwd: nil) else { return [] }
        // java_home -V 的列表输出在 stderr
        let text = result.standardError.isEmpty ? result.standardOutput : result.standardError

        var found: [JDK] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // 形如: 21.0.7 (arm64) "Eclipse Adoptium" - "OpenJDK 21.0.7" /Library/.../Contents/Home
            guard let pathRange = line.range(of: #"(/[^\s].*)$"#, options: .regularExpression) else { continue }
            let home = String(line[pathRange])
            guard home.hasSuffix("/Home") || home.contains(".jdk") else { continue }

            let head = String(line[line.startIndex..<pathRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard let versionToken = head.split(separator: " ").first else { continue }
            let parts = versionToken.split(separator: ".").compactMap { Int($0) }
            guard let major = parts.first else { continue }
            let fullVersion = parts.count >= 3
                ? "\(parts[0]).\(parts[1]).\(parts[2])"
                : String(versionToken)

            let vendor = firstQuoted(head) ?? ""

            found.append(JDK(version: major, fullVersion: fullVersion,
                             vendor: vendor, home: home, isCurrent: false))
        }

        // 标记系统默认 JDK
        if let cur = Shell.run("/usr/libexec/java_home", args: [], cwd: nil) {
            let defaultHome = cur.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !defaultHome.isEmpty {
                for i in found.indices where found[i].home == defaultHome {
                    found[i].isCurrent = true
                }
            }
        }

        // 按 home 去重,保留首次出现
        var seen = Set<String>()
        var unique: [JDK] = []
        for j in found where !seen.contains(j.home) {
            seen.insert(j.home)
            unique.append(j)
        }
        return unique.sorted { $0.version > $1.version }
    }

    private static func firstQuoted(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "\"") else { return nil }
        let rest = s[s.index(after: start)...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<end])
    }

    /// 为指定版本选择最合适的 JDK,找不到返回 nil
    static func resolve(version: Int?) -> JDK? {
        let all = installedJDKs()
        guard !all.isEmpty else { return nil }
        guard let version else {
            return all.first(where: { $0.isCurrent }) ?? all.first
        }
        // 精确匹配优先
        if let exact = all.first(where: { $0.version == version }) { return exact }
        // 否则取 >= 需求版本中最低的
        let higher = all.filter { $0.version >= version }.sorted { $0.version < $1.version }
        return higher.first ?? all.first
    }
}
