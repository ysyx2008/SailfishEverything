#!/usr/bin/swift
import AppKit
import Foundation

let repo = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .resolvingSymlinksInPath()
let resources = repo.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let inset = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
        let radius = size * 0.22
        let body = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        NSColor(calibratedRed: 0.04, green: 0.27, blue: 0.34, alpha: 1).setFill()
        body.fill()

        let sheen = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.58, alpha: 0.55),
            NSColor(calibratedRed: 0.04, green: 0.27, blue: 0.34, alpha: 0),
        ])?.draw(in: sheen, angle: 90)

        let ink = NSColor(calibratedRed: 0.93, green: 0.97, blue: 0.96, alpha: 1)
        ink.setStroke()
        ink.setFill()

        let cx = rect.midX + size * 0.08
        let cy = rect.midY - size * 0.02
        let lensR = size * 0.16
        let lens = NSBezierPath(ovalIn: NSRect(x: cx - lensR, y: cy - lensR, width: lensR * 2, height: lensR * 2))
        lens.lineWidth = max(2, size * 0.055)
        lens.stroke()

        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: cx + lensR * 0.72, y: cy - lensR * 0.72))
        handle.line(to: NSPoint(x: cx + lensR * 1.45, y: cy - lensR * 1.45))
        handle.lineWidth = max(2, size * 0.06)
        handle.lineCapStyle = .round
        handle.stroke()

        let lineWidth = size * 0.045
        let lineLeft = inset.minX + size * 0.16
        let lineRight = cx - lensR - size * 0.08
        if lineRight > lineLeft + size * 0.08 {
            for (index, widthFactor) in [1.0, 0.82, 0.64].enumerated() {
                let y = rect.midY + size * 0.12 - CGFloat(index) * size * 0.11
                let line = NSBezierPath()
                line.move(to: NSPoint(x: lineLeft, y: y))
                line.line(to: NSPoint(x: lineLeft + (lineRight - lineLeft) * widthFactor, y: y))
                line.lineWidth = lineWidth
                line.lineCapStyle = .round
                line.stroke()
            }
        }
        return true
    }
}

let master = drawIcon(size: 1024)
let pngURL = resources.appendingPathComponent("AppIcon-1024.png")
guard let tiff = master.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode icon\n", stderr)
    exit(1)
}
try png.write(to: pngURL)

let iconset = resources.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let slices: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, pixel) in slices {
    let image = drawIcon(size: pixel)
    image.size = NSSize(width: pixel, height: pixel)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent(name))
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(process.terminationStatus)
}
try? FileManager.default.removeItem(at: iconset)
print("wrote \(icns.path)")
