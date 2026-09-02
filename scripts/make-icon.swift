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
    a > 200 && Int(r) + Int(g) + Int(b) < 600
}

func rowFillColors(width: Int, height: Int, data: [UInt8]) -> [(UInt8, UInt8, UInt8)] {
    var colors = Array(repeating: (UInt8(0), UInt8(0), UInt8(0)), count: height)
    var found = Array(repeating: false, count: height)
    let center = width / 2
    for y in 0..<height {
        var color: (UInt8, UInt8, UInt8)?
        var dx = 0
        while dx <= center, color == nil {
            for x in [center - dx, center + dx] where x >= 0 && x < width {
                let i = (y * width + x) * 4
                if isBackgroundPixel(r: data[i], g: data[i + 1], b: data[i + 2], a: data[i + 3]) {
                    color = (data[i], data[i + 1], data[i + 2])
                    break
                }
            }
            dx += 1
        }
        if let color {
            colors[y] = color
            found[y] = true
        }
    }
    var last = (UInt8(10), UInt8(40), UInt8(70))
    for y in 0..<height {
        if found[y] {
            last = colors[y]
        } else {
            colors[y] = last
        }
    }
    for y in stride(from: height - 1, through: 0, by: -1) {
        if found[y] {
            last = colors[y]
        } else {
            colors[y] = last
        }
    }
    return colors
}

func darkMargin(width: Int, height: Int, data: [UInt8]) -> Int {
    var insets: [Int] = []
    for y in (height * 2 / 5)..<(height * 3 / 5) {
        var left = 0
        while left < width / 3 {
            let i = (y * width + left) * 4
            if Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2]) > 90 { break }
            left += 1
        }
        var right = 0
        while right < width / 3 {
            let i = (y * width + (width - 1 - right)) * 4
            if Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2]) > 90 { break }
            right += 1
        }
        insets.append(min(left, right))
    }
    guard !insets.isEmpty else { return 0 }
    let sorted = insets.sorted()
    return sorted[sorted.count / 2]
}

func renderSquare(_ src: CGImage, crop: CGRect, pixelSize: Int, fills: [(UInt8, UInt8, UInt8)]) -> CGImage {
    let count = pixelSize * pixelSize * 4
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
    buffer.initialize(repeating: 255, count: count)
    defer { buffer.deallocate() }
    for y in 0..<pixelSize {
        let sourceY = min(fills.count - 1, Int(crop.minY) + (y * Int(crop.height)) / pixelSize)
        let color = fills[max(0, sourceY)]
        for x in 0..<pixelSize {
            let i = (y * pixelSize + x) * 4
            buffer[i] = color.0
            buffer[i + 1] = color.1
            buffer[i + 2] = color.2
            buffer[i + 3] = 255
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
    guard let context else {
        fputs("failed to compose icon\n", stderr)
        exit(1)
    }
    context.interpolationQuality = .high
    let drawn = src.cropping(to: crop) ?? src
    context.draw(drawn, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    guard let image = context.makeImage() else {
        fputs("failed to compose icon\n", stderr)
        exit(1)
    }
    return image
}

func makeMaster(from source: CGImage, pixelSize: Int) -> CGImage {
    let sampled = pixels(from: source)
    let fills = rowFillColors(width: sampled.width, height: sampled.height, data: sampled.data)
    let inset = darkMargin(width: sampled.width, height: sampled.height, data: sampled.data)
    let cropAmount = inset >= max(8, sampled.width / 30) ? inset : 0
    let crop = CGRect(
        x: cropAmount,
        y: cropAmount,
        width: sampled.width - cropAmount * 2,
        height: sampled.height - cropAmount * 2
    )
    return renderSquare(source, crop: crop, pixelSize: pixelSize, fills: fills)
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
