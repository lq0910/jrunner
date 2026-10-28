import Foundation

// MARK: - 版本信息

/// 版本号的唯一来源是打包时写进 Info.plist 的 `CFBundleShortVersionString`
/// (该值由根目录 `VERSION` 文件经 `scripts/build_app.sh` 注入)。
///
/// 直接用 `swift run` 跑时没有 bundle,`infoDictionary` 拿不到值,
/// 此时回退到 "dev",不会显示成误导性的正式版本号。
enum AppVersion {
    static let fallback = "dev"

    /// 短版本号,如 `1.0.0`
    static var short: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        guard let v, !v.isEmpty, !v.contains("__") else { return fallback }
        return v
    }

    /// 构建号(CI 上是 run number,本地是 git 提交数)
    static var build: String {
        let v = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        guard let v, !v.isEmpty, !v.contains("__") else { return "-" }
        return v
    }

    /// 带前缀的展示文本,如 `v1.0.0`
    static var display: String { "v\(short)" }

    /// 是否跑在正式 bundle 里(而不是 `swift run`)
    static var isBundled: Bool { short != fallback }
}
