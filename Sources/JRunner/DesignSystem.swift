import SwiftUI
import AppKit

// MARK: - 主题色(自动跟随系统深浅色)

extension Color {
    /// 构造随外观自动切换的颜色
    static func jrDynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// 主色
    static let jrPrimary = Color.jrDynamic(
        light: NSColor(srgbRed: 0.09, green: 0.45, blue: 0.82, alpha: 1),
        dark:  NSColor(srgbRed: 0.29, green: 0.60, blue: 0.98, alpha: 1)
    )
    /// 选中态浅底
    static let jrPrimaryLight = Color.jrDynamic(
        light: NSColor(srgbRed: 0.93, green: 0.96, blue: 1.00, alpha: 1),
        dark:  NSColor(srgbRed: 0.14, green: 0.23, blue: 0.36, alpha: 1)
    )
    static let jrSuccess = Color.jrDynamic(
        light: NSColor(srgbRed: 0.06, green: 0.62, blue: 0.35, alpha: 1),
        dark:  NSColor(srgbRed: 0.28, green: 0.80, blue: 0.52, alpha: 1)
    )
    static let jrWarning = Color.jrDynamic(
        light: NSColor(srgbRed: 0.85, green: 0.50, blue: 0.06, alpha: 1),
        dark:  NSColor(srgbRed: 0.98, green: 0.70, blue: 0.26, alpha: 1)
    )
    static let jrDanger = Color.jrDynamic(
        light: NSColor(srgbRed: 0.80, green: 0.19, blue: 0.19, alpha: 1),
        dark:  NSColor(srgbRed: 0.96, green: 0.40, blue: 0.38, alpha: 1)
    )
    static let jrPurple = Color.jrDynamic(
        light: NSColor(srgbRed: 0.51, green: 0.31, blue: 0.79, alpha: 1),
        dark:  NSColor(srgbRed: 0.74, green: 0.57, blue: 0.98, alpha: 1)
    )

    /// 页面底色
    static let jrBg = Color.jrDynamic(
        light: NSColor(srgbRed: 0.965, green: 0.968, blue: 0.975, alpha: 1),
        dark:  NSColor(srgbRed: 0.105, green: 0.110, blue: 0.120, alpha: 1)
    )
    /// 卡片/面板底色
    static let jrCard = Color.jrDynamic(
        light: NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        dark:  NSColor(srgbRed: 0.150, green: 0.156, blue: 0.168, alpha: 1)
    )
    /// 分隔线/描边
    static let jrBorder = Color.jrDynamic(
        light: NSColor(srgbRed: 0.87, green: 0.88, blue: 0.90, alpha: 1),
        dark:  NSColor(srgbRed: 0.255, green: 0.265, blue: 0.285, alpha: 1)
    )
    static let jrTextPrimary = Color.jrDynamic(
        light: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1),
        dark:  NSColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1)
    )
    static let jrTextSecondary = Color.jrDynamic(
        light: NSColor(srgbRed: 0.42, green: 0.45, blue: 0.49, alpha: 1),
        dark:  NSColor(srgbRed: 0.69, green: 0.71, blue: 0.74, alpha: 1)
    )
    static let jrTextTertiary = Color.jrDynamic(
        light: NSColor(srgbRed: 0.62, green: 0.65, blue: 0.68, alpha: 1),
        dark:  NSColor(srgbRed: 0.52, green: 0.55, blue: 0.59, alpha: 1)
    )
    /// 卡片投影(深色下几乎不可见,单独给深色值)
    static let jrShadow = Color.jrDynamic(
        light: NSColor.black.withAlphaComponent(0.05),
        dark:  NSColor.black.withAlphaComponent(0.35)
    )
}

// MARK: - 日志级别配色

extension LogLevel {
    var color: Color {
        switch self {
        case .error:  return .jrDanger
        case .warn:   return .jrWarning
        case .info:   return .jrTextSecondary
        case .debug:  return .jrTextTertiary
        case .plain:  return .jrTextPrimary
        }
    }

    var label: String {
        switch self {
        case .error: return "错误"
        case .warn:  return "警告"
        case .info:  return "信息"
        case .debug: return "调试"
        case .plain: return "输出"
        }
    }
}

// MARK: - 通用组件

/// 圆角卡片容器
struct CardModifier: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.jrCard)
                    .shadow(color: Color.jrShadow, radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.jrBorder.opacity(0.7), lineWidth: 0.5)
            )
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// 徽章标签
struct Badge: View {
    var text: String
    var color: Color
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(filled ? color.opacity(0.9) : color.opacity(0.13))
            )
            .foregroundStyle(filled ? Color.white : color)
    }
}

/// 主行动按钮
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .jrPrimary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 次要按钮
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = .jrTextSecondary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .foregroundStyle(tint)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.jrBorder.opacity(configuration.isPressed ? 0.9 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.jrBorder, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 状态指示灯(呼吸光环用时间轴驱动,不依赖 repeatForever,避免动画残留)
struct StatusDot: View {
    var state: TaskState

    private var isActive: Bool { state == .running || state == .starting }

    var body: some View {
        ZStack {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.4) / 1.4
                    Circle()
                        .stroke(dotColor.opacity(0.40 * (1 - t)), lineWidth: 1.6)
                        .frame(width: 8 + 13 * t, height: 8 + 13 * t)
                }
            }
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
        }
        .frame(width: 8, height: 8)
    }

    private var dotColor: Color {
        switch state {
        case .idle: return .jrTextTertiary
        case .starting, .running: return .jrSuccess
        case .stopping: return .jrWarning
        case .success: return .jrSuccess
        case .failed: return .jrDanger
        }
    }
}

/// 可旋转图标:角度由时间轴计算,停止时角度固定为 0
/// (之前用 repeatForever + rotationEffect,停止后动画仍会残留导致图标抖动/飘动)
struct SpinningIcon: View {
    var systemName: String
    var isSpinning: Bool
    var size: CGFloat = 11
    var weight: Font.Weight = .semibold
    var color: Color = .jrPrimary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isSpinning)) { ctx in
            let angle = isSpinning
                ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
                : 0
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: size + 4, height: size + 4)
    }
}

/// 可拖拽的竖向分隔条
struct SplitHandle: View {
    @Binding var width: CGFloat
    var minValue: CGFloat
    var maxValue: CGFloat

    @State private var hovering = false
    @State private var dragStart: CGFloat?

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(hovering ? Color.jrPrimary.opacity(0.55) : Color.jrBorder.opacity(0.55))
                .frame(width: hovering ? 2 : 1)
        }
        .frame(width: 7)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let base = dragStart ?? width
                    if dragStart == nil { dragStart = base }
                    width = min(max(minValue, base + value.translation.width), max(minValue, maxValue))
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}

/// Git 分支徽章
struct BranchBadge: View {
    enum Style {
        /// 胶囊底 + 彩色文字,用于标题栏 / 面板头部
        case prominent
        /// 纯文字,用于侧边栏行尾
        case subtle
    }

    var status: GitStatus
    var style: Style = .prominent

    private var tint: Color { status.isDetached ? .jrWarning : .jrPurple }

    var body: some View {
        switch style {
        case .prominent:
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold))
                Text(status.branch)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                if status.isDirty {
                    Circle().fill(tint).frame(width: 4.5, height: 4.5)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.5))

        case .subtle:
            HStack(spacing: 2.5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 7.5, weight: .semibold))
                Text(status.branch)
                    .font(.system(size: 8.8, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(Color.jrTextTertiary)
        }
    }
}

/// 自动订阅 GitMonitor 的分支徽章(点击可手动刷新)
struct GitBranchBadge: View {
    @ObservedObject var monitor: GitMonitor
    var path: String?
    var style: BranchBadge.Style = .prominent
    var maxWidth: CGFloat?

    var body: some View {
        if let path, let status = monitor.status(for: path), status.isRepo {
            if style == .prominent {
                BranchBadge(status: status, style: style)
                    .frame(maxWidth: maxWidth, alignment: .trailing)
                    .help(status.tooltip + "\n(点击刷新)")
                    .onTapGesture { monitor.refresh(path: path, force: true) }
            } else {
                BranchBadge(status: status, style: style)
                    .frame(maxWidth: maxWidth, alignment: .trailing)
                    .help(status.tooltip)
            }
        }
    }
}

/// 可切换分支的徽章:点开是本地分支列表,选中即 checkout。
/// 样式全部加在 Menu 外层 —— SwiftUI 会把 `.borderlessButton` 标签内部的
/// padding / background 丢掉,写在里面胶囊底会消失。
struct BranchSwitcher: View {
    @ObservedObject var monitor: GitMonitor
    @ObservedObject var store: AppStore
    var path: String
    var maxTextWidth: CGFloat = 150

    private var tint: Color { status?.isDetached == true ? .jrWarning : .jrPurple }

    private var status: GitStatus? { monitor.status(for: path) }
    private var list: [String] { monitor.branches(for: path) }

    var body: some View {
        if let status, status.isRepo {
            Menu {
                if list.isEmpty {
                    Text("正在读取分支…")
                } else {
                    ForEach(list, id: \.self) { b in
                        Toggle(isOn: Binding(
                            get: { b == status.branch },
                            set: { _ in
                                guard b != status.branch else { return }
                                store.switchBranch(b, projectPath: path)
                            }
                        )) {
                            Text(b)
                        }
                    }
                }

                Divider()

                Button("刷新分支列表") {
                    monitor.loadBranches(path: path)
                    monitor.refresh(path: path, force: true)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .semibold))
                    Text(status.branch)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: maxTextWidth, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5, weight: .bold))
                        .opacity(0.65)
                    if status.isDirty {
                        Circle().fill(tint).frame(width: 4.5, height: 4.5)
                    }
                }
                .foregroundStyle(tint)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(monitor.isCheckingOut)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 0.5))
            .help(status.tooltip + "\n点击切换分支")
        }
    }
}

/// 空状态提示
struct EmptyStateView: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.jrTextTertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.jrTextSecondary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.jrTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
