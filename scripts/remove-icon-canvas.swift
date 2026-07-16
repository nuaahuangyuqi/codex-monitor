#!/usr/bin/swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO

private let backgroundThreshold: UInt8 = 10
private let transparentThreshold: UInt8 = 3

func removeConnectedDarkCanvas(at path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(domain: "IconCanvas", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "无法读取图标：\(path)"
        ])
    }

    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
        | CGImageAlphaInfo.premultipliedLast.rawValue
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

    let didDraw = pixels.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(
            data: storage.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return false }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard didDraw else { throw NSError(domain: "IconCanvas", code: 2) }

    var visited = [Bool](repeating: false, count: width * height)
    var queue: [Int] = []
    queue.reserveCapacity(width * height / 4)

    func enqueue(_ x: Int, _ y: Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let index = y * width + x
        guard !visited[index] else { return }
        visited[index] = true
        queue.append(index)
    }

    for x in 0..<width {
        enqueue(x, 0)
        enqueue(x, height - 1)
    }
    for y in 0..<height {
        enqueue(0, y)
        enqueue(width - 1, y)
    }

    var cursor = 0
    while cursor < queue.count {
        let index = queue[cursor]
        cursor += 1
        let x = index % width
        let y = index / width
        let offset = y * bytesPerRow + x * 4
        let brightness = max(pixels[offset], pixels[offset + 1], pixels[offset + 2])
        guard brightness <= backgroundThreshold else { continue }

        let alpha: UInt8
        if brightness <= transparentThreshold {
            alpha = 0
        } else {
            alpha = UInt8(
                (Int(brightness - transparentThreshold) * 255)
                    / Int(backgroundThreshold - transparentThreshold)
            )
        }
        pixels[offset] = UInt8((Int(pixels[offset]) * Int(alpha)) / 255)
        pixels[offset + 1] = UInt8((Int(pixels[offset + 1]) * Int(alpha)) / 255)
        pixels[offset + 2] = UInt8((Int(pixels[offset + 2]) * Int(alpha)) / 255)
        pixels[offset + 3] = alpha

        enqueue(x - 1, y)
        enqueue(x + 1, y)
        enqueue(x, y - 1)
        enqueue(x, y + 1)
    }

    let result: CGImage? = pixels.withUnsafeMutableBytes { storage in
        guard let context = CGContext(
            data: storage.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        return context.makeImage()
    }
    guard let result else { throw NSError(domain: "IconCanvas", code: 3) }

    let representation = NSBitmapImageRep(cgImage: result)
    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconCanvas", code: 4)
    }
    try png.write(to: url, options: .atomic)
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: remove-icon-canvas.swift <png> [png ...]\n", stderr)
    exit(2)
}

do {
    for path in CommandLine.arguments.dropFirst() {
        try removeConnectedDarkCanvas(at: path)
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
