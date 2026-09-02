#!/usr/bin/swift
// 程序坞图标以 Resources/AppIcon-1024.png 为准；本脚本把稿铺满方图画进 icns。
// 换稿：swift scripts/make-icon.swift /path/to/designed.png
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repo = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .resolvingSymlinksInPath()
let resources = repo.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

let pngURL = resources.appendingPathComponent("AppIcon-1024.png")
let sourceURL = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : pngURL

guard FileManager.default.fileExists(atPath: sourceURL.path) else {
    fputs("missing icon source: \(sourceURL.path)\n", stderr)
    exit(1)
}

func cgImage(from url: URL) -> CGImage {
    guard let image = NSImage(contentsOf: url),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fputs("failed to read \(url.path)\n", stderr)
        exit(1)
    }
    return cg
}

func pixels(from image: CGImage) -> (width: Int, height: Int, data: [UInt8]) {
    let width = image.width
    let height = image.height
    let count = width * height * 4
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    buffer.initialize(repeating: 0, count: count)
    defer { buffer.deallocate() }
    let context = CGContext(
        data: buffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let context else {
        fputs("failed to read pixels\n", stderr)
        exit(1)
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, Array(UnsafeBufferPointer(start: buffer, count: count)))
}

func isBackgroundPixel(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> Bool {
    a > 200 && b > r && Int(r) + Int(g) + Int(b) < 420
}

func smoothGradient(width: Int, height: Int, data: [UInt8], stops: Int) -> [(UInt8, UInt8, UInt8)] {
    var samples: [(t: Double, color: (Double, Double, Double))] = []
    let xs = [width / 6, width / 5, width * 4 / 5, width * 5 / 6]
    for step in 0..<max(4, stops) {
        let y = height / 8 + (step * height * 6 / 8) / max(stops - 1, 1)
        var r = 0, g = 0, b = 0, n = 0
        for x in xs where x >= 0 && x < width {
            let i = (y * width + x) * 4
            if isBackgroundPixel(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3]) {
                r += Int(data[i]); g += Int(data[i + 1]); b += Int(data[i + 2]); n += 1
            }
        }
        if n > 0 {
            samples.append((Double(step) / Double(max(stops - 1, 1)), (Double(r / n), Double(g / n), Double(b / n))))
        }
    }
    if samples.isEmpty {
        samples = [(0, (8, 28, 70)), (1, (20, 110, 200))]
    }
    if samples.count == 1 {
        samples.append((1, samples[0].color))
    }
    var colors = Array(repeating: (UInt8(10), UInt8(40), UInt8(80)), count: 1024)
    for i in 0..<colors.count {
        let t = Double(i) / Double(colors.count - 1)
        var lo = samples.first!, hi = samples.last!
        for pair in zip(samples, samples.dropFirst()) where t >= pair.0.t {
            lo = pair.0
            hi = pair.1
        }
        let span = max(0.0001, hi.t - lo.t)
        let u = min(1, max(0, (t - lo.t) / span))
        colors[i] = (
            UInt8((lo.color.0 + (hi.color.0 - lo.color.0) * u).rounded()),
            UInt8((lo.color.1 + (hi.color.1 - lo.color.1) * u).rounded()),
            UInt8((lo.color.2 + (hi.color.2 - lo.color.2) * u).rounded())
        )
    }
    return colors
}

func makeMaster(from source: CGImage, pixelSize: Int) -> CGImage {
    composeIcon(from: pixels(from: source), pixelSize: pixelSize)
}

func samplePixel(_ data: [UInt8], width: Int, height: Int, x: Double, y: Double) -> (UInt8, UInt8, UInt8, UInt8)? {
    if x < 0 || y < 0 || x >= Double(width - 1) || y >= Double(height - 1) { return nil }
    let x0 = Int(x), y0 = Int(y)
    let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
    let fx = x - Double(x0), fy = y - Double(y0)
    func pix(_ px: Int, _ py: Int) -> (Double, Double, Double, Double) {
        let i = (py * width + px) * 4
        return (Double(data[i]), Double(data[i + 1]), Double(data[i + 2]), Double(data[i + 3]))
    }
    let p00 = pix(x0, y0), p10 = pix(x1, y0), p01 = pix(x0, y1), p11 = pix(x1, y1)
    func mix(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double), _ t: Double) -> (Double, Double, Double, Double) {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t, a.3 + (b.3 - a.3) * t)
    }
    let top = mix(p00, p10, fx)
    let bot = mix(p01, p11, fx)
    let p = mix(top, bot, fy)
    return (UInt8(p.0.rounded()), UInt8(p.1.rounded()), UInt8(p.2.rounded()), UInt8(p.3.rounded()))
}

func isInk(_ data: [UInt8], width: Int, x: Int, y: Int) -> Bool {
    let i = (y * width + x) * 4
    return data[i] >= 200 && data[i + 1] >= 200 && data[i + 2] >= 200
}

func composeIcon(from sampled: (width: Int, height: Int, data: [UInt8]), pixelSize: Int) -> CGImage {
    let fills = smoothGradient(width: sampled.width, height: sampled.height, data: sampled.data, stops: 12)
    let edge = max(24, sampled.width / 10)
    var minX = sampled.width, minY = sampled.height, maxX = 0, maxY = 0
    var count = 0
    for y in edge..<(sampled.height - edge) {
        for x in edge..<(sampled.width - edge) {
            if !isInk(sampled.data, width: sampled.width, x: x, y: y) { continue }
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
            count += 1
        }
    }
    let cx = count > 0 ? Double(minX + maxX) / 2 : Double(sampled.width) / 2
    let cy = count > 0 ? Double(minY + maxY) / 2 : Double(sampled.height) / 2
    let pad = max(8, (max(maxX - minX, maxY - minY)) / 25)
    minX = max(edge, minX - pad)
    minY = max(edge, minY - pad)
    maxX = min(sampled.width - 1 - edge, maxX + pad)
    maxY = min(sampled.height - 1 - edge, maxY + pad)
    let extent = max(
        max(cx - Double(minX), Double(maxX) - cx),
        max(cy - Double(minY), Double(maxY) - cy)
    )
    let target = Double(pixelSize) * 0.38
    let scale = extent > 0 ? target / extent : 1
    let bytes = pixelSize * pixelSize * 4
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes)
    buffer.initialize(repeating: 255, count: bytes)
    defer { buffer.deallocate() }
    let mid = Double(pixelSize) / 2
    for y in 0..<pixelSize {
        let fill = fills[min(fills.count - 1, (y * (fills.count - 1)) / max(pixelSize - 1, 1))]
        for x in 0..<pixelSize {
            let i = (y * pixelSize + x) * 4
            buffer[i] = fill.0
            buffer[i + 1] = fill.1
            buffer[i + 2] = fill.2
            buffer[i + 3] = 255
            let srcX = cx + (Double(x) + 0.5 - mid) / scale
            let srcY = cy + (Double(y) + 0.5 - mid) / scale
            guard srcX >= Double(minX), srcX <= Double(maxX), srcY >= Double(minY), srcY <= Double(maxY) else { continue }
            guard let pix = samplePixel(sampled.data, width: sampled.width, height: sampled.height, x: srcX, y: srcY) else { continue }
            if pix.0 >= 188, pix.1 >= 188, pix.2 >= 188 {
                buffer[i] = pix.0
                buffer[i + 1] = pix.1
                buffer[i + 2] = pix.2
            }
        }
    }
    let context = CGContext(
        data: buffer,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let context, let image = context.makeImage() else {
        fputs("failed to compose icon\n", stderr)
        exit(1)
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fputs("failed to write \(url.path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("failed to write \(url.path)\n", stderr)
        exit(1)
    }
}

func scaled(_ image: CGImage, to pixel: Int) -> CGImage {
    let count = pixel * pixel * 4
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    buffer.initialize(repeating: 0, count: count)
    defer { buffer.deallocate() }
    let context = CGContext(
        data: buffer,
        width: pixel,
        height: pixel,
        bitsPerComponent: 8,
        bytesPerRow: pixel * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let context else {
        fputs("failed to scale icon\n", stderr)
        exit(1)
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixel, height: pixel))
    guard let scaled = context.makeImage() else {
        fputs("failed to scale icon\n", stderr)
        exit(1)
    }
    return scaled
}

func writeMenuBarTemplate(_ image: CGImage, to url: URL, pixelSize: Int) {
    let sampled = pixels(from: image)
    var minX = sampled.width, minY = sampled.height, maxX = 0, maxY = 0
    for y in 0..<sampled.height {
        for x in 0..<sampled.width {
            let i = (y * sampled.width + x) * 4
            if sampled.data[i] < 200 || sampled.data[i + 1] < 200 || sampled.data[i + 2] < 200 { continue }
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
    }
    guard maxX > minX, maxY > minY else {
        fputs("failed to extract menu bar icon\n", stderr)
        exit(1)
    }
    let pad = max(4, (max(maxX - minX, maxY - minY)) / 30)
    minX = max(0, minX - pad)
    minY = max(0, minY - pad)
    maxX = min(sampled.width - 1, maxX + pad)
    maxY = min(sampled.height - 1, maxY + pad)
    let cropW = maxX - minX + 1
    let cropH = maxY - minY + 1
    let side = max(cropW, cropH)
    let originX = minX - (side - cropW) / 2
    let originY = minY - (side - cropH) / 2
    let count = pixelSize * pixelSize * 4
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    buffer.initialize(repeating: 0, count: count)
    defer { buffer.deallocate() }
    for y in 0..<pixelSize {
        for x in 0..<pixelSize {
            let srcX = originX + (x * side) / pixelSize
            let srcY = originY + (y * side) / pixelSize
            guard srcX >= 0, srcX < sampled.width, srcY >= 0, srcY < sampled.height else { continue }
            let src = (srcY * sampled.width + srcX) * 4
            let i = (y * pixelSize + x) * 4
            if sampled.data[src] >= 190, sampled.data[src + 1] >= 190, sampled.data[src + 2] >= 190 {
                buffer[i + 3] = 255
            }
        }
    }
    let context = CGContext(
        data: buffer,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    guard let context, let template = context.makeImage() else {
        fputs("failed to extract menu bar icon\n", stderr)
        exit(1)
    }
    writePNG(template, to: url)
}

let master = makeMaster(from: cgImage(from: sourceURL), pixelSize: 1024)
writePNG(master, to: pngURL)
let menuBarURL = resources.appendingPathComponent("MenuBarIcon.png")
writeMenuBarTemplate(master, to: menuBarURL, pixelSize: 64)

let iconset = resources.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let slices: [(String, Int)] = [
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
    writePNG(scaled(master, to: pixel), to: iconset.appendingPathComponent(name))
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
print("wrote \(pngURL.path)")
print("wrote \(icns.path)")
print("wrote \(menuBarURL.path)")
