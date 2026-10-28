//
// 生成 icon_1024.png —— JRunner 的图标源图。
//
// 用法:swift scripts/make_icon.swift [输出路径]
//
// 设计:橙色渐变的圆角方块 + 白色咖啡杯(Java 的梗),和标题栏里的
// 应用内 logo 同一套配色,视觉上是连续的。
//
// 这张图是仓库里的唯一图标来源,build_app.sh 只负责把它切成 .icns。
// 想改图标就改这里再重新生成,别直接改 JRunner.app 里的 icns(那个是产物)。
//
import AppKit
import Foundation

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

// MARK: - 把 SF Symbol 染成指定颜色

func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let symbol = base.withSymbolConfiguration(config) else {
        FileHandle.standardError.write("找不到 SF Symbol: \(name)\n".data(using: .utf8)!)
        exit(1)
    }

    let img = NSImage(size: symbol.size)
    img.lockFocus()
    symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
    color.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    img.unlockFocus()
    return img
}

// MARK: - 画布

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write("创建位图失败\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// 透明底
NSColor.clear.set()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// MARK: - 圆角方块(macOS 图标网格:内容约占 82%)

let inset = size * 0.09
let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = plate.width * 0.2237          // 接近 macOS squircle 的圆角比例
let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

// 主体渐变:上浅橙 → 下深橙,和标题栏 logo 完全一致
let top = NSColor(srgbRed: 1.00, green: 0.78, blue: 0.36, alpha: 1)
let bottom = NSColor(srgbRed: 0.91, green: 0.41, blue: 0.15, alpha: 1)
NSGradient(starting: top, ending: bottom)?.draw(in: platePath, angle: -90)

// 顶部一层很淡的高光,避免大面积纯渐变显得平
NSGraphicsContext.saveGraphicsState()
platePath.addClip()
NSGradient(starting: NSColor(white: 1, alpha: 0.20),
           ending: NSColor(white: 1, alpha: 0.0))?
    .draw(in: NSRect(x: plate.minX, y: plate.midY,
                     width: plate.width, height: plate.height / 2),
          angle: -90)
NSGraphicsContext.restoreGraphicsState()

// 内描边:让边缘在浅色桌面上也有轮廓
NSColor(white: 1, alpha: 0.22).setStroke()
platePath.lineWidth = size * 0.004
platePath.stroke()

// MARK: - 咖啡杯

let cup = tintedSymbol("cup.and.saucer.fill", pointSize: size * 0.52, color: .white)
let targetWidth = plate.width * 0.60
let scale = targetWidth / cup.size.width
let cupSize = NSSize(width: cup.size.width * scale, height: cup.size.height * scale)
let cupRect = NSRect(
    x: plate.midX - cupSize.width / 2,
    y: plate.midY - cupSize.height / 2 + plate.height * 0.015,   // 视觉重心略微上移
    width: cupSize.width,
    height: cupSize.height
)

// 杯子下方一层柔和投影,做出一点厚度
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(srgbRed: 0.45, green: 0.14, blue: 0.02, alpha: 0.35)
shadow.shadowBlurRadius = size * 0.015
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
shadow.set()
cup.draw(in: cupRect, from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()

// MARK: - 写出

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 编码失败\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("已生成 \(outPath)(\(png.count / 1024) KB)")
