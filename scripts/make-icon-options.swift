#!/usr/bin/swift
import AppKit
import Foundation

let repo = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .resolvingSymlinksInPath()
let out = repo.appendingPathComponent("dist/icon-options")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func unit(_ x: CGFloat, _ y: CGFloat, in box: NSRect) -> NSPoint {
    NSPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
}

func sailfishPath(in box: NSRect) -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { unit(x, y, in: box) }
    let fish = NSBezierPath()
    fish.move(to: p(0.97, 0.54))
    fish.line(to: p(0.76, 0.58))
    fish.curve(to: p(0.64, 0.60), controlPoint1: p(0.72, 0.63), controlPoint2: p(0.68, 0.62))
    fish.line(to: p(0.60, 0.94))
    fish.curve(to: p(0.38, 0.62), controlPoint1: p(0.54, 0.90), controlPoint2: p(0.42, 0.74))
    fish.curve(to: p(0.24, 0.58), controlPoint1: p(0.32, 0.60), controlPoint2: p(0.28, 0.60))
    fish.line(to: p(0.03, 0.80))
    fish.curve(to: p(0.17, 0.51), controlPoint1: p(0.10, 0.70), controlPoint2: p(0.17, 0.58))
    fish.curve(to: p(0.04, 0.22), controlPoint1: p(0.17, 0.44), controlPoint2: p(0.10, 0.30))
    fish.line(to: p(0.24, 0.42))
    fish.curve(to: p(0.64, 0.38), controlPoint1: p(0.34, 0.34), controlPoint2: p(0.50, 0.32))
    fish.curve(to: p(0.76, 0.46), controlPoint1: p(0.70, 0.36), controlPoint2: p(0.74, 0.40))
    fish.line(to: p(0.97, 0.54))
    fish.close()
    return fish
}

func speedLines(in box: NSRect) -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { unit(x, y, in: box) }
    let lines = NSBezierPath()
    lines.lineCapStyle = .round
    for (start, end) in [
        (p(0.02, 0.62), p(0.14, 0.58)),
        (p(0.00, 0.50), p(0.13, 0.50)),
        (p(0.03, 0.38), p(0.15, 0.42)),
    ] {
        lines.move(to: start)
        lines.line(to: end)
    }
    return lines
}

func glassRing(center: NSPoint, radius: CGFloat, handle: CGFloat, width: CGFloat) -> NSBezierPath {
    let ring = NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
    ring.lineWidth = width
    let stem = NSBezierPath()
    let angle: CGFloat = -.pi / 4
    stem.move(to: NSPoint(
        x: center.x + cos(angle) * (radius + width * 0.15),
        y: center.y + sin(angle) * (radius + width * 0.15)
    ))
    stem.line(to: NSPoint(
        x: center.x + cos(angle) * (radius + handle),
        y: center.y + sin(angle) * (radius + handle)
    ))
    stem.lineWidth = width
    stem.lineCapStyle = .round
    ring.append(stem)
    return ring
}

func fillSquircle(_ rect: NSRect, size: CGFloat) {
    let inset = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
    let radius = size * 0.22
    let body = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.04, green: 0.27, blue: 0.34, alpha: 1).setFill()
    body.fill()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.58, alpha: 0.55),
        NSColor(calibratedRed: 0.04, green: 0.27, blue: 0.34, alpha: 0),
    ])?.draw(in: NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius), angle: 90)
}

let ink = NSColor(calibratedRed: 0.93, green: 0.97, blue: 0.96, alpha: 1)

enum Option: String, CaseIterable {
    case a = "A-只留旗鱼"
    case b = "B-镜里有鱼"
    case c = "C-鱼从镜里冲出"
    case d = "D-大鱼小镜"
}

func drawApp(_ option: Option, size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        fillSquircle(rect, size: size)
        ink.setFill()
        ink.setStroke()
        let inset = rect.insetBy(dx: size * 0.13, dy: size * 0.13)
        switch option {
        case .a:
            let box = inset.insetBy(dx: 0, dy: size * 0.02)
            sailfishPath(in: box).fill()
            if size >= 64 {
                let lines = speedLines(in: box)
                lines.lineWidth = max(1.5, size * 0.018)
                lines.stroke()
            }
        case .b:
            let cx = rect.midX - size * 0.04
            let cy = rect.midY + size * 0.05
            let radius = size * 0.26
            let width = max(2, size * 0.055)
            let ring = glassRing(center: NSPoint(x: cx, y: cy), radius: radius, handle: size * 0.20, width: width)
            ring.stroke()
            let fishBox = NSRect(x: cx - radius * 0.72, y: cy - radius * 0.55, width: radius * 1.35, height: radius * 1.05)
            sailfishPath(in: fishBox).fill()
        case .c:
            let cx = rect.midX - size * 0.02
            let cy = rect.midY
            let radius = size * 0.24
            let width = max(2, size * 0.05)
            glassRing(center: NSPoint(x: cx, y: cy), radius: radius, handle: size * 0.18, width: width).stroke()
            let fishBox = NSRect(
                x: rect.minX + size * 0.16,
                y: rect.minY + size * 0.22,
                width: size * 0.70,
                height: size * 0.56
            )
            sailfishPath(in: fishBox).fill()
            if size >= 64 {
                let lines = speedLines(in: NSRect(
                    x: rect.minX + size * 0.10,
                    y: rect.minY + size * 0.30,
                    width: size * 0.28,
                    height: size * 0.28
                ))
                lines.lineWidth = max(1.5, size * 0.016)
                lines.stroke()
            }
        case .d:
            let fishBox = inset.insetBy(dx: size * 0.02, dy: size * 0.04)
            sailfishPath(in: fishBox).fill()
            let glass = glassRing(
                center: NSPoint(x: rect.minX + size * 0.28, y: rect.minY + size * 0.28),
                radius: size * 0.08,
                handle: size * 0.07,
                width: max(1.5, size * 0.028)
            )
            glass.stroke()
        }
        return true
    }
}

func drawMenu(_ option: Option, point: CGFloat) -> NSImage {
    let pixel = point * 2
    let image = NSImage(size: NSSize(width: point, height: point))
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixel),
        pixelsHigh: Int(pixel),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: pixel, height: pixel)
    NSColor.clear.setFill()
    rect.fill()
    NSColor.black.setFill()
    NSColor.black.setStroke()
    let box = rect.insetBy(dx: pixel * 0.08, dy: pixel * 0.16)
    switch option {
    case .a, .d:
        sailfishPath(in: box).fill()
    case .b:
        let ring = glassRing(
            center: NSPoint(x: rect.midX - pixel * 0.04, y: rect.midY + pixel * 0.04),
            radius: pixel * 0.28,
            handle: pixel * 0.20,
            width: pixel * 0.08
        )
        ring.stroke()
        sailfishPath(in: NSRect(x: rect.midX - pixel * 0.26, y: rect.midY - pixel * 0.10, width: pixel * 0.40, height: pixel * 0.30)).fill()
    case .c:
        glassRing(
            center: NSPoint(x: rect.midX, y: rect.midY),
            radius: pixel * 0.24,
            handle: pixel * 0.16,
            width: pixel * 0.07
        ).stroke()
        sailfishPath(in: box).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(rep)
    image.isTemplate = true
    return image
}

func writePNG(_ image: NSImage, name: String) throws {
    image.size = image.size
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fputs("failed \(name)\n", stderr)
        return
    }
    try data.write(to: out.appendingPathComponent(name))
}

func drawSheet() -> NSImage {
    let cell: CGFloat = 280
    let pad: CGFloat = 24
    let menu: CGFloat = 36
    let width = pad + (cell + pad) * 4
    let height = pad + cell + pad + menu + pad + 36
    return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        rect.fill()
        for (index, option) in Option.allCases.enumerated() {
            let x = pad + CGFloat(index) * (cell + pad)
            drawApp(option, size: cell).draw(in: NSRect(x: x, y: pad + menu + pad + 28, width: cell, height: cell))
            let menuIcon = drawMenu(option, point: menu)
            menuIcon.isTemplate = false
            NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
            let bar = NSBezierPath(roundedRect: NSRect(x: x + (cell - 72) / 2, y: pad + 28, width: 72, height: 48), xRadius: 8, yRadius: 8)
            bar.fill()
            menuIcon.draw(in: NSRect(x: x + (cell - menu) / 2, y: pad + 34, width: menu, height: menu))
            let label = option.rawValue as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: x + (cell - size.width) / 2, y: 8), withAttributes: attrs)
        }
        return true
    }
}

for option in Option.allCases {
    try writePNG(drawApp(option, size: 1024), name: "\(option.rawValue)-1024.png")
    try writePNG(drawApp(option, size: 128), name: "\(option.rawValue)-128.png")
    try writePNG(drawMenu(option, point: 18), name: "\(option.rawValue)-菜单栏.png")
}
try writePNG(drawSheet(), name: "对照.png")
print("wrote \(out.path)")
