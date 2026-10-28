import SwiftUI
import AppKit

// MARK: - 外观模式

/// 深色 / 浅色 / 跟随系统。
///
/// 直接改 `NSApp.appearance` 而不是 SwiftUI 的 `.preferredColorScheme`:
/// 后者只作用于窗口内容,标题栏、弹窗、菜单仍然是系统外观,深色下会「半黑半白」。
/// 设成 nil 即恢复跟随系统。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// 当前是否处于深色(跟随系统时取系统实际外观)
    var isDark: Bool {
        switch self {
        case .light: return false
        case .dark:  return true
        case .system:
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua
        }
    }

    func apply() {
        switch self {
        case .system: NSApp?.appearance = nil
        case .light:  NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static let storageKey = "appearanceMode"

    /// 从 UserDefaults 读回上次的选择
    static func stored() -> AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}

// MARK: - 标题栏用的外观切换菜单

struct AppearanceMenu: View {
    @Binding var mode: AppearanceMode

    var body: some View {
        Menu {
            Picker("外观", selection: $mode) {
                ForEach(AppearanceMode.allCases) { m in
                    Label(m.label, systemImage: m.icon).tag(m)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.jrTextSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.jrTextSecondary.opacity(0.001))
        )
        .help("外观:\(mode.label)")
    }
}
