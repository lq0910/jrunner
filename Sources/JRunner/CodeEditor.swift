import SwiftUI
import AppKit

// MARK: - 语言识别

enum SyntaxLanguage: Equatable {
    case yaml, properties, java, kotlin, xml, json, sql, markdown, shell, plain

    static func from(ext: String) -> SyntaxLanguage {
        switch ext.lowercased() {
        case "yml", "yaml": return .yaml
        case "properties", "conf", "env", "ini": return .properties
        case "java": return .java
        case "kt", "kts", "gradle": return .kotlin
        case "xml", "html", "htm", "plist": return .xml
        case "json": return .json
        case "sql": return .sql
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh": return .shell
        default: return .plain
        }
    }
}

// MARK: - 配色(随外观切换)

struct SyntaxTheme {
    let keyword: NSColor
    let string: NSColor
    let comment: NSColor
    let number: NSColor
    let type: NSColor
    let annotation: NSColor
    let key: NSColor
    let punctuation: NSColor

    static func forAppearance(_ appearance: NSAppearance) -> SyntaxTheme {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if isDark {
            return SyntaxTheme(
                keyword:     NSColor(srgbRed: 0.98, green: 0.47, blue: 0.64, alpha: 1),  // 粉
                string:      NSColor(srgbRed: 0.62, green: 0.87, blue: 0.56, alpha: 1),  // 绿
                comment:     NSColor(srgbRed: 0.47, green: 0.51, blue: 0.56, alpha: 1),  // 灰
                number:      NSColor(srgbRed: 0.87, green: 0.74, blue: 0.52, alpha: 1),  // 沙
                type:        NSColor(srgbRed: 0.45, green: 0.80, blue: 0.96, alpha: 1),  // 青
                annotation:  NSColor(srgbRed: 0.82, green: 0.64, blue: 0.99, alpha: 1),  // 紫
                key:         NSColor(srgbRed: 0.51, green: 0.82, blue: 0.96, alpha: 1),
                punctuation: NSColor(srgbRed: 0.62, green: 0.65, blue: 0.69, alpha: 1)
            )
        }
        return SyntaxTheme(
            keyword:     NSColor(srgbRed: 0.72, green: 0.10, blue: 0.42, alpha: 1),
            string:      NSColor(srgbRed: 0.13, green: 0.45, blue: 0.16, alpha: 1),
            comment:     NSColor(srgbRed: 0.52, green: 0.55, blue: 0.58, alpha: 1),
            number:      NSColor(srgbRed: 0.60, green: 0.35, blue: 0.05, alpha: 1),
            type:        NSColor(srgbRed: 0.10, green: 0.35, blue: 0.62, alpha: 1),
            annotation:  NSColor(srgbRed: 0.48, green: 0.25, blue: 0.70, alpha: 1),
            key:         NSColor(srgbRed: 0.09, green: 0.32, blue: 0.58, alpha: 1),
            punctuation: NSColor(srgbRed: 0.35, green: 0.37, blue: 0.40, alpha: 1)
        )
    }
}

// MARK: - 高亮规则

enum SyntaxHighlighter {

    struct Rule {
        let pattern: String
        let color: KeyPath<SyntaxTheme, NSColor>
        var options: NSRegularExpression.Options = []
    }

    static func rules(for language: SyntaxLanguage) -> [Rule] {
        switch language {
        case .yaml:
            return [
                Rule(pattern: #"(?m)^[ \t]*#.*$"#, color: \.comment),
                Rule(pattern: #"(?m)^[ \t]*(?:-[ \t]*)?([A-Za-z_][\w.\-]*)(?=[ \t]*:)"#, color: \.key),
                Rule(pattern: #""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'"#, color: \.string),
                Rule(pattern: #"\$\{[^}]+\}"#, color: \.annotation),
                Rule(pattern: #"(?<![\w.-])-?\d+(?:\.\d+)?(?![\w.-])"#, color: \.number),
                Rule(pattern: #"\b(?:true|false|null|yes|no|on|off)\b"#, color: \.keyword, options: [.caseInsensitive]),
            ]
        case .properties:
            return [
                Rule(pattern: #"(?m)^[ \t]*[#!].*$"#, color: \.comment),
                Rule(pattern: #"(?m)^[ \t]*([^=:\s]+)[ \t]*[=:]"#, color: \.key),
                Rule(pattern: #"\$\{[^}]+\}"#, color: \.annotation),
                Rule(pattern: #"(?<![\w.-])\d+(?:\.\d+)?(?![\w.-])"#, color: \.number),
                Rule(pattern: #"\b(?:true|false)\b"#, color: \.keyword),
            ]
        case .java, .kotlin:
            return [
                Rule(pattern: #"(?m)//.*$"#, color: \.comment),
                Rule(pattern: #"/\*[\s\S]*?\*/"#, color: \.comment),
                Rule(pattern: #""(?:[^"\\]|\\.)*""#, color: \.string),
                Rule(pattern: #"@[A-Za-z_]\w*"#, color: \.annotation),
                Rule(pattern: #"\b(?:public|private|protected|internal|class|interface|object|enum|fun|val|var|return|if|else|when|for|while|try|catch|finally|throw|new|package|import|extends|implements|static|final|abstract|override|open|data|suspend|inline|const|lateinit|companion|init|constructor|this|super|null|true|false|void|int|long|double|float|boolean|char|byte|short|String|Int|Long|Double|Float|Boolean|Any|Unit|List|Map|Set|MutableList|MutableMap|Repository|Service|Controller|Component|Configuration)\b"#, color: \.keyword),
                Rule(pattern: #"\b[A-Z][A-Za-z0-9_]*\b"#, color: \.type),
                Rule(pattern: #"(?<![\w.])\d+(?:\.\d+)?[fFlLdD]?(?![\w.])"#, color: \.number),
            ]
        case .xml:
            return [
                Rule(pattern: #"<!--[\s\S]*?-->"#, color: \.comment),
                Rule(pattern: #"</?[A-Za-z_][\w.:-]*"#, color: \.keyword),
                Rule(pattern: #"[A-Za-z_][\w.:-]*(?==)"#, color: \.key),
                Rule(pattern: #""[^"]*""#, color: \.string),
                Rule(pattern: #"<\?[\s\S]*?\?>"#, color: \.annotation),
            ]
        case .json:
            return [
                Rule(pattern: #""(?:[^"\\]|\\.)*"(?=\s*:)"#, color: \.key),
                Rule(pattern: #""(?:[^"\\]|\\.)*""#, color: \.string),
                Rule(pattern: #"(?<![\w.])-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?(?![\w.])"#, color: \.number),
                Rule(pattern: #"\b(?:true|false|null)\b"#, color: \.keyword),
            ]
        case .sql:
            return [
                Rule(pattern: #"--.*$"#, color: \.comment),
                Rule(pattern: #"/\*[\s\S]*?\*/"#, color: \.comment),
                Rule(pattern: #"'(?:[^'\\]|\\.)*'"#, color: \.string),
                Rule(pattern: #"\b(?:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|INDEX|ALTER|DROP|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|AS|AND|OR|NOT|NULL|IS|IN|EXISTS|DISTINCT|COUNT|SUM|AVG|MAX|MIN|CASE|WHEN|THEN|ELSE|END|PRIMARY|KEY|FOREIGN|REFERENCES|DEFAULT|UNIQUE)\b"#, color: \.keyword, options: [.caseInsensitive]),
                Rule(pattern: #"(?<![\w.])\d+(?:\.\d+)?(?![\w.])"#, color: \.number),
            ]
        case .markdown:
            return [
                Rule(pattern: #"(?m)^#{1,6}[ \t].*$"#, color: \.keyword),
                Rule(pattern: #"`[^`\n]+`"#, color: \.string),
                Rule(pattern: #"(?m)^[ \t]*[-*+][ \t]"#, color: \.annotation),
                Rule(pattern: #"\[[^\]]*\]\([^)]*\)"#, color: \.type),
                Rule(pattern: #"(?m)^>.*$"#, color: \.comment),
            ]
        case .shell:
            return [
                Rule(pattern: #"(?m)^[ \t]*#.*$"#, color: \.comment),
                Rule(pattern: #""(?:[^"\\]|\\.)*"|'[^']*'"#, color: \.string),
                Rule(pattern: #"\$\{?\w+\}?"#, color: \.annotation),
                Rule(pattern: #"\b(?:if|then|else|fi|for|do|done|while|case|esac|function|return|export|local|echo|cd|exit)\b"#, color: \.keyword),
            ]
        case .plain:
            return []
        }
    }

    /// 计算高亮区间(后匹配的规则会覆盖先匹配的,所以顺序即优先级)
    static func highlight(_ text: String, language: SyntaxLanguage, theme: SyntaxTheme) -> [(NSRange, NSColor)] {
        let rules = rules(for: language)
        guard !rules.isEmpty else { return [] }
        let full = NSRange(location: 0, length: (text as NSString).length)
        guard full.length > 0 else { return [] }
        var result: [(NSRange, NSColor)] = []

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            let color = theme[keyPath: rule.color]
            regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match, match.range.length > 0 else { return }
                result.append((match.range, color))
            }
        }
        return result
    }
}

// MARK: - 文本视图(外观变化时通知重绘)

final class CodeTextView: NSTextView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

// MARK: - 行号栏

final class LineNumberRuler: NSRulerView {

    /// 每行起始字符位置(升序),用于二分查找行号
    private(set) var lineStarts: [Int] = [0]
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    /// 当前行数
    var lineCount: Int { lineStarts.count }

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = scrollView.documentView
    }

    required init(coder: NSCoder) { fatalError() }

    /// 重新计算每行起始位置,并按行数调整栏宽
    func rebuildLineStarts(_ text: String) {
        var starts: [Int] = [0]
        starts.reserveCapacity(max(16, text.count / 32))
        let ns = text as NSString
        var i = 0
        while i < ns.length {
            if ns.character(at: i) == 0x0A { starts.append(i + 1) }
            i += 1
        }
        lineStarts = starts

        let digits = max(2, String(starts.count).count)
        let width = CGFloat(digits) * 6.6 + 18
        if abs(ruleThickness - width) > 0.5 {
            ruleThickness = width
        }
        needsDisplay = true
    }

    private func lineNumber(at charIndex: Int) -> Int {
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= charIndex { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        // 背景:比正文底色稍作区分,形成层次
        let base = textView.backgroundColor
        let blended = base.blended(withFraction: 0.06, of: .labelColor) ?? base
        blended.setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let inset = textView.textContainerInset.height

        let attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] fragRect, _, _, _, _ in
            guard let self else { return }
            let glyphIndex = layoutManager.glyphIndex(for: NSPoint(x: 0, y: fragRect.midY), in: container)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let number = self.lineNumber(at: charIndex)

            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attrs)
            let y = fragRect.minY + inset + (fragRect.height - size.height) / 2
            label.draw(at: NSPoint(x: self.ruleThickness - size.width - 9, y: y),
                       withAttributes: attrs)
        }
    }
}

// MARK: - 代码编辑器

struct CodeEditor: NSViewRepresentable {

    @Binding var text: String
    let language: SyntaxLanguage
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // 显式搭 TextKit 1 栈,保证 layoutManager 可用
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let textView = CodeTextView(frame: .zero, textContainer: container)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.font = Coordinator.editorFont
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        // 文档视图给一个初始尺寸,避免首帧零尺寸导致的布局抖动
        textView.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 400))
        textView.setFrameSize(NSSize(width: max(1, scrollView.contentSize.width),
                                     height: max(1, textView.frame.height)))

        // 行号栏
        let ruler = LineNumberRuler(scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        ruler.rebuildLineStarts(text)
        textView.onAppearanceChange = { [weak coordinator = context.coordinator, weak ruler] in
            DispatchQueue.main.async {
                coordinator?.applyHighlight(force: true)
                ruler?.needsDisplay = true
            }
        }
        context.coordinator.applyHighlight(force: true)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self

        let languageChanged = coordinator.lastLanguage != language
        if languageChanged { coordinator.lastLanguage = language }

        // 外部文本变化(切换文件)时同步
        if textView.string != text {
            textView.string = text
            coordinator.ruler?.rebuildLineStarts(text)
            coordinator.applyHighlight(force: true)
            return
        }
        if languageChanged {
            coordinator.applyHighlight(force: true)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        static let editorFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

        var parent: CodeEditor
        weak var textView: CodeTextView?
        weak var ruler: LineNumberRuler?
        var lastLanguage: SyntaxLanguage?
        private var highlightWork: DispatchWorkItem?

        init(_ parent: CodeEditor) {
            self.parent = parent
            self.lastLanguage = parent.language
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            parent.onChange()
            ruler?.rebuildLineStarts(textView.string)
            scheduleHighlight()
        }

        private func scheduleHighlight() {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.applyHighlight(force: false) }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
        }

        /// 用 temporary attributes 上色:不污染文本存储,不影响撤销与查找
        func applyHighlight(force: Bool) {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textStorage = textView.textStorage else { return }

            let length = textStorage.length
            let full = NSRange(location: 0, length: length)

            let theme = SyntaxTheme.forAppearance(textView.effectiveAppearance)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

            // 超大文件不上色,避免卡顿
            guard length < 400_000 else { return }

            for (range, color) in SyntaxHighlighter.highlight(textView.string,
                                                              language: parent.language,
                                                              theme: theme) {
                guard range.location >= 0, range.location + range.length <= length else { continue }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
            }
        }
    }
}
