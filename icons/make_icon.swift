// 生成 macOS SF Symbol 模板图标（用于 Hammerspoon 菜单栏）
// 用法: swift make_icon.swift <symbolName> <outputPng> [pointSize]
// 例:   swift make_icon.swift photo.on.rectangle ~/.hammerspoon/icons/unsplashz.png
//
// 输出为「黑色 + 透明通道」的 PNG，配合 hs.menubar:setIcon(path, true)
// 作为 template image 使用，可随菜单栏明暗自动反色。

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("用法: make_icon.swift <symbolName> <outputPng> [pointSize]\n".data(using: .utf8)!)
    exit(1)
}

let symbolName = args[1]
let outPath = args[2]
let pointSize = args.count >= 4 ? (CGFloat(Double(args[3]) ?? 18.0)) : 18.0
let scale: CGFloat = 2   // Retina 2x

let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
      let img = base.withSymbolConfiguration(cfg) else {
    FileHandle.standardError.write("SF Symbol 不存在: \(symbolName)\n".data(using: .utf8)!)
    exit(2)
}

let size = NSSize(width: pointSize, height: pointSize)
let w = Int(size.width * scale), h = Int(size.height * scale)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    exit(3)
}
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(4) }
let outURL = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
try? FileManager.default.createDirectory(atPath: outURL.deletingLastPathComponent().path,
                                        withIntermediateDirectories: true)
try png.write(to: outURL)
print("OK \(symbolName) -> \(outURL.path) (\(w)x\(h)px @\(pointSize)pt)")
