import SwiftUI
import AppKit

@main
struct JRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            MainView(store: store)
                .frame(minWidth: 1080, minHeight: 640)
                .onAppear {
                    store.scanProjects()
                }
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // 替换系统默认的「关于」,让版本号带上构建号
            CommandGroup(replacing: .appInfo) {
                Button("关于 JRunner") {
                    let credits = NSAttributedString(
                        string: "轻量级 Java / Kotlin 服务启动器\nMIT License · github.com/lq0910/jrunner",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "JRunner",
                        .applicationVersion: AppVersion.short,
                        .version: "构建 \(AppVersion.build)",
                        .credits: credits
                    ])
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            CommandMenu("操作") {
                Button("重新扫描项目") {
                    store.scanProjects()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("启动服务") {
                    if let m = store.selectedModule { store.run(module: m) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("打包") {
                    if let m = store.selectedModule { store.build(module: m) }
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("停止") {
                    if let m = store.selectedModule { store.stop(module: m) }
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                Button("保存文件") {
                    if store.editor.save() {
                        store.statusMessage = "已保存 \(store.editor.fileName)"
                        store.refreshGit()
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!store.editor.isDirty)

                Button("设置") {
                    store.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 未捕获异常写日志,便于排查(不阻止崩溃,但留下线索)
        NSSetUncaughtExceptionHandler { exception in
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/JRunner", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let log = dir.appendingPathComponent("crash.log")
            let text = """
            [\(Date())] \(exception.name.rawValue)
            reason: \(exception.reason ?? "-")
            stack:
            \(exception.callStackSymbols.joined(separator: "\n"))

            """
            if let handle = try? FileHandle(forWritingTo: log) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
            } else {
                try? text.write(to: log, atomically: true, encoding: .utf8)
            }
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 回到前台时重读分支(可能刚在终端 / 其他工具里切过分支)
    func applicationDidBecomeActive(_ notification: Notification) {
        AppStore.shared?.refreshGit(force: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出前停掉所有子进程,避免遗留 gradle / java 进程
        AppStore.shared?.stopAll()
    }
}
