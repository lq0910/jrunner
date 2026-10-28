import SwiftUI
import Combine

// MARK: - 日志控制台

struct LogConsole: View {
    @ObservedObject var store: AppStore
    @State private var filterText: String = ""
    @State private var levelFilter: LogLevel = .plain
    @State private var filterEnabled = false
    @State private var autoScroll = true
    @State private var task: ProcessTask?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Color.jrBorder.opacity(0.6))

            if let task, let summary = Self.errorSummary(task) {
                errorBanner(summary)
            }

            if let task {
                LogView(task: task, filterText: filterText, levelFilter: levelFilter,
                       filterEnabled: filterEnabled, autoScroll: autoScroll)
            } else {
                EmptyStateView(
                    icon: "terminal",
                    title: "暂无运行日志",
                    subtitle: "启动或打包模块后,这里会实时显示输出"
                )
            }
        }
        .background(Color.jrCard)
        .onChange(of: store.activeTaskID) { newValue in
            task = newValue.flatMap { id in store.tasks.values.first { $0.id == id } }
        }
        .onAppear {
            if let project = store.selectedProject, let m = store.selectedModule {
                task = store.task(for: project, module: m)
            }
        }
        .onChange(of: store.selectedProject?.id) { _ in
            if let project = store.selectedProject, let m = store.selectedModule {
                task = store.task(for: project, module: m)
            } else {
                task = nil
            }
        }
        .onChange(of: store.selectedModule?.id) { _ in
            // 切换模块时同步到该模块自己的任务(没有任务就清空)
            if let project = store.selectedProject, let m = store.selectedModule {
                task = store.task(for: project, module: m)
            } else {
                task = nil
            }
        }
    }

    /// 从日志里提炼失败根因,避免用户翻几百行找原因
    static func errorSummary(_ task: ProcessTask) -> String? {
        guard case .failed = task.state else { return nil }
        let texts = task.lines.map { $0.text.trimmingCharacters(in: .whitespaces) }

        // 最具体的异常链优先
        if let idx = texts.lastIndex(where: { $0.hasPrefix("Caused by:") }) {
            return texts[idx].replacingOccurrences(of: "Caused by: ", with: "")
        }
        if let idx = texts.lastIndex(where: { $0.contains("APPLICATION FAILED TO START") }) {
            // 后面通常跟 Description/Action
            if idx + 2 < texts.count { return texts[idx + 2] }
            return texts[idx]
        }
        if let idx = texts.lastIndex(where: { $0.contains("What went wrong") }) {
            if idx + 1 < texts.count { return texts[idx + 1] }
        }
        if let last = texts.last(where: { !$0.isEmpty && !$0.hasPrefix("BUILD FAILED") }) {
            return last
        }
        return nil
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.jrDanger)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.jrDanger)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jrDanger.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("复制失败原因")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.jrDanger.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.jrDanger.opacity(0.2)).frame(height: 0.5)
        }
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            // 第一行:标题 + 状态 + 视图控制
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.jrTextTertiary)
                    .fixedSize()

                if let task {
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.jrTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    StatusDot(state: task.state)
                        .fixedSize()
                } else {
                    Text("控制台")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.jrTextSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                // 级别筛选
                Menu {
                    Button("全部") { levelFilter = .plain }
                    Divider()
                    Button("仅错误") { levelFilter = .error }
                    Button("错误 + 警告") { levelFilter = .warn }
                    Button("含调试") { levelFilter = .debug }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(levelFilter == .plain ? Color.jrTextTertiary : levelFilter.color)
                            .frame(width: 6, height: 6)
                        Text(levelFilter == .plain ? "全部" : levelFilter.label)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    autoScroll.toggle()
                } label: {
                    Image(systemName: autoScroll ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                        .font(.system(size: 11))
                        .foregroundStyle(autoScroll ? Color.jrPrimary : Color.jrTextTertiary)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(autoScroll ? "自动滚动已开启" : "自动滚动已暂停")

                if let task {
                    Button {
                        task.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.jrTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("清空日志")
                }
            }

            // 第二行:过滤框 + 执行的命令
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(filterEnabled ? Color.jrPrimary : Color.jrTextTertiary)
                    TextField("过滤日志", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onChange(of: filterText) { newValue in
                            filterEnabled = !newValue.isEmpty
                        }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.jrCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(Color.jrBorder.opacity(0.8), lineWidth: 0.5)
                )
                .frame(width: 132)

                if let task {
                    Text(task.subtitle)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.jrTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.jrBg)
    }
}

// MARK: - 日志视图

private struct LogView: View {
    @ObservedObject var task: ProcessTask
    let filterText: String
    let levelFilter: LogLevel
    let filterEnabled: Bool
    let autoScroll: Bool

    private var visibleLines: [LogLine] {
        var result = task.lines
        // 级别过滤
        switch levelFilter {
        case .plain: break
        case .error: result = result.filter { $0.level == .error }
        case .warn:  result = result.filter { $0.level == .error || $0.level == .warn }
        case .info:  result = result.filter { $0.level != .debug }
        case .debug: break
        }
        // 文本过滤
        if filterEnabled && !filterText.isEmpty {
            let q = filterText.lowercased()
            result = result.filter { $0.text.lowercased().contains(q) }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        LogLineRow(line: line)
                            .id(line.id)
                    }
                    // 滚动锚点
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.jrCard)
            .onChange(of: task.lines.count) { _ in
                guard autoScroll else { return }
                withAnimation(.linear(duration: 0.08)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - 单行日志

private struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 时间戳
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.jrTextTertiary.opacity(0.8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 78, alignment: .leading)

            // 级别标记
            Text(marker)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(line.level.color)
                .padding(.trailing, 6)
                .frame(width: 12, alignment: .leading)

            // 内容
            Text(line.text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(line.level == .plain ? Color.jrTextPrimary : line.level.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
    }

    private var rowBackground: Color {
        switch line.level {
        case .error: return Color.jrDanger.opacity(0.05)
        case .warn:  return Color.jrWarning.opacity(0.05)
        default: return .clear
        }
    }

    private var marker: String {
        switch line.level {
        case .error: return "!"
        case .warn:  return "▲"
        case .debug: return "·"
        default: return ""
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: line.timestamp)
    }
}
