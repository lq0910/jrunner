import Foundation
import Combine

/// 日志级别
enum LogLevel: String {
    case error, warn, info, debug, plain

    static func detect(_ line: String) -> LogLevel {
        let l = line.uppercased()
        if l.contains("ERROR") || l.contains("EXCEPTION") || l.contains("FAILED") || l.contains("FATAL") { return .error }
        if l.contains("WARN") { return .warn }
        if l.contains("DEBUG") || l.contains("TRACE") { return .debug }
        if l.contains("INFO") { return .info }
        return .plain
    }
}

/// 一条日志
struct LogLine: Identifiable {
    let id = UUID()
    let text: String
    let level: LogLevel
    let timestamp: Date
}

/// 运行中的任务状态
enum TaskState: Equatable {
    case idle
    case starting
    case running
    case stopping
    case success
    case failed(String)

    var isActive: Bool { self == .starting || self == .running || self == .stopping }
}

/// 后台任务:运行一个命令并实时捕获输出
final class ProcessTask: ObservableObject, Identifiable {

    let id = UUID()
    let command: PlannedCommand
    let title: String
    let subtitle: String

    @Published private(set) var state: TaskState = .idle
    @Published private(set) var lines: [LogLine] = []
    /// 从日志里识别到的服务端口(如 "Tomcat started on port 8080")
    @Published private(set) var detectedPort: Int?
    /// 环形缓冲上限,防止内存爆炸
    private let maxLines: Int

    private var process: Process?
    private let pendingLock = NSLock()
    private var pending: [LogLine] = []
    private var flushScheduled = false

    init(command: PlannedCommand, title: String, subtitle: String, maxLines: Int = 20000) {
        self.command = command
        self.title = title
        self.subtitle = subtitle
        self.maxLines = maxLines
    }

    // MARK: - 启动

    func start() {
        guard state == .idle else { return }
        state = .starting

        let p = Process()
        p.executableURL = URL(fileURLWithPath: command.executable)
        p.arguments = command.arguments
        p.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory)

        // 合并环境变量
        var env = ProcessInfo.processInfo.environment
        for (k, v) in command.environment { env[k] = v }
        env["TERM"] = "dumb"          // 关闭 ANSI 颜色/光标控制
        env["CI"] = "false"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        self.process = p
        append(LogLine(text: "$ " + command.displayCommand, level: .debug, timestamp: Date()))

        do {
            try p.run()
        } catch {
            state = .failed(error.localizedDescription)
            append(LogLine(text: "启动失败: \(error.localizedDescription)", level: .error, timestamp: Date()))
            return
        }

        state = .running

        // 用 terminationHandler 检测退出,不用 waitUntilExit。
        // 原因:Gradle/Maven 会拉起常驻守护进程继承 stdout 管道,
        // 管道不关闭时 waitUntilExit 永远不返回,任务状态就会卡在「运行中」。
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            // 关闭读端,唤醒可能阻塞在 availableData 的读取线程
            try? pipe.fileHandleForReading.close()
            DispatchQueue.main.async {
                guard let self else { return }
                self.flushNow()
                if self.state == .stopping {
                    self.state = .success
                    self.append(LogLine(text: "进程已停止", level: .warn, timestamp: Date()))
                } else if status == 0 {
                    self.state = .success
                    self.append(LogLine(text: "✅ 执行成功", level: .info, timestamp: Date()))
                } else {
                    self.state = .failed("退出码 \(status)")
                    self.append(LogLine(text: "❌ 执行失败,退出码 \(status)", level: .error, timestamp: Date()))
                }
            }
        }

        // 流式按行读取
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                while let idx = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<idx)
                    buffer.removeSubrange(buffer.startIndex...idx)
                    if let raw = String(data: lineData, encoding: .utf8) {
                        let clean = ProcessTask.stripANSI(raw)
                        self.append(LogLine(text: clean, level: LogLevel.detect(clean), timestamp: Date()))
                    }
                }
                // 防止超长单行撑爆内存
                if buffer.count > 1_000_000 {
                    if let raw = String(data: buffer, encoding: .utf8) {
                        let clean = ProcessTask.stripANSI(raw)
                        self.append(LogLine(text: clean, level: LogLevel.detect(clean), timestamp: Date()))
                    }
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            if !buffer.isEmpty, let raw = String(data: buffer, encoding: .utf8) {
                let clean = ProcessTask.stripANSI(raw)
                if !clean.isEmpty {
                    self.append(LogLine(text: clean, level: LogLevel.detect(clean), timestamp: Date()))
                }
            }
        }
    }

    // MARK: - 停止

    /// 先 SIGTERM,5 秒后仍在运行则 SIGKILL
    func stop() {
        guard let p = process, p.isRunning else { return }
        state = .stopping
        append(LogLine(text: "正在停止进程...", level: .warn, timestamp: Date()))

        let pid = p.processIdentifier
        let port = detectedPort
        p.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            // 1. 客户端进程仍在 → 强杀
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
                DispatchQueue.main.async {
                    self?.append(LogLine(text: "进程已强制结束", level: .error, timestamp: Date()))
                }
            }

            // 2. Gradle / Maven 会把应用 JVM 交给常驻守护进程托管,
            //    客户端退出后应用可能仍在占用端口,这里按端口兜底清理。
            //    只清理 java 进程,避免误杀恰好占用同端口的其他程序。
            if let port {
                let pids = ProcessTask.listeningPIDs(port: port).filter { ProcessTask.isJavaProcess($0) }
                guard !pids.isEmpty else { return }
                for target in pids { kill(target, SIGTERM) }
                Thread.sleep(forTimeInterval: 1.5)
                for target in ProcessTask.listeningPIDs(port: port).filter({ ProcessTask.isJavaProcess($0) }) {
                    kill(target, SIGKILL)
                }
                DispatchQueue.main.async {
                    self?.append(LogLine(text: "已释放端口 \(port)", level: .info, timestamp: Date()))
                }
            }
        }
    }

    /// 判断 PID 是否为 java 进程(避免误杀同端口的其他服务)
    static func isJavaProcess(_ pid: Int32) -> Bool {
        guard let r = Shell.run("/bin/ps", args: ["-p", "\(pid)", "-o", "comm="], cwd: nil) else { return false }
        let name = r.standardOutput.lowercased()
        return name.contains("java")
    }

    /// 查询监听指定端口的进程 PID
    static func listeningPIDs(port: Int) -> [Int32] {
        guard let r = Shell.run("/usr/sbin/lsof", args: ["-ti", "tcp:\(port)", "-sTCP:LISTEN"], cwd: nil) else { return [] }
        return r.standardOutput
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    // MARK: - 日志

    /// 清空日志
    func clearLogs() {
        pendingLock.lock()
        pending.removeAll()
        pendingLock.unlock()
        DispatchQueue.main.async {
            self.lines.removeAll()
        }
    }

    /// 追加日志:先入队,50ms 内合并刷新,避免高频 dispatch 拖垮主线程
    private func append(_ line: LogLine) {
        pendingLock.lock()
        pending.append(line)
        let needSchedule = !flushScheduled
        if needSchedule { flushScheduled = true }
        pendingLock.unlock()

        if needSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.flushNow()
            }
        }
    }

    /// 把队列里的日志一次性合并进 lines(主线程)
    private func flushNow() {
        pendingLock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        flushScheduled = false
        pendingLock.unlock()

        guard !batch.isEmpty else { return }
        lines.append(contentsOf: batch)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        // 顺带从新日志里识别端口
        if detectedPort == nil {
            for l in batch {
                if let p = ProcessTask.extractPort(l.text) {
                    detectedPort = p
                    break
                }
            }
        }
    }

    /// 从 Spring Boot / Tomcat 日志里提取监听端口
    static func extractPort(_ text: String) -> Int? {
        // 匹配: on port 8080 / with port(s): 8080 / port: 8080
        guard let r = text.range(of: #"\bport(?:\(s\))?[:\s]+(\d{2,5})\b"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }
        let digits = String(text[r]).filter { $0.isNumber }
        guard let p = Int(digits), p > 0, p <= 65535 else { return nil }
        return p
    }

    /// 剥离 ANSI 转义序列
    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        return s.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }

    deinit {
        if let p = process, p.isRunning {
            kill(p.processIdentifier, SIGTERM)
        }
    }
}
