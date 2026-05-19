#!/usr/bin/env swift
import AppKit

enum IconGenerationError: Error {
    case missingSource(URL)
    case unreadableSource(URL)
    case bitmapEncodingFailed(URL)
    case iconutilFailed(Int32)
}

struct IconRenderer {
    let sourceImage: NSImage
    let canvasSize: CGFloat

    func render(to url: URL) throws {
        let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
        image.lockFocus()

        let canvas = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
        NSColor(calibratedWhite: 0.72, alpha: 1).setFill()
        canvas.fill()

        let drawRect = aspectFitRect(
            imageSize: sourceImage.size,
            in: canvas
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        sourceImage.draw(
            in: drawRect,
            from: CGRect(origin: .zero, size: sourceImage.size),
            operation: .sourceOver,
            fraction: 1
        )

        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw IconGenerationError.bitmapEncodingFailed(url)
        }

        try png.write(to: url)
    }

    private func aspectFitRect(imageSize: NSSize, in bounds: CGRect) -> CGRect {
        let widthRatio = bounds.width / imageSize.width
        let heightRatio = bounds.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)
        let width = imageSize.width * ratio
        let height = imageSize.height * ratio

        return CGRect(
            x: bounds.midX - (width / 2),
            y: bounds.midY - (height / 2),
            width: width,
            height: height
        )
    }
}

let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDirectory = projectDirectory.appendingPathComponent("Packaging/Resources")
let sourceURL = resourcesDirectory.appendingPathComponent("PublicanIconSource.jpg")
let iconsetDirectory = resourcesDirectory.appendingPathComponent("Publican.iconset")

guard FileManager.default.fileExists(atPath: sourceURL.path) else {
    throw IconGenerationError.missingSource(sourceURL)
}

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw IconGenerationError.unreadableSource(sourceURL)
}

try FileManager.default.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

let entries: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in entries {
    try IconRenderer(sourceImage: sourceImage, canvasSize: size)
        .render(to: iconsetDirectory.appendingPathComponent(filename))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c",
    "icns",
    iconsetDirectory.path,
    "-o",
    resourcesDirectory.appendingPathComponent("Publican.icns").path
]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus != 0 {
    throw IconGenerationError.iconutilFailed(iconutil.terminationStatus)
}

print(resourcesDirectory.appendingPathComponent("Publican.icns").path)
