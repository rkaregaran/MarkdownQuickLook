#!/usr/bin/env swift

import AppKit

let size: CGFloat = 1024
let cgSize = NSSize(width: size, height: size)

let image = NSImage(size: cgSize)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Failed to get graphics context")
}

// Background gradient: dark lavender (top) to light lavender (bottom)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradientColors = [
    CGColor(red: 0.24, green: 0.16, blue: 0.36, alpha: 1.0), // #3D2A5C dark lavender
    CGColor(red: 0.91, green: 0.88, blue: 0.94, alpha: 1.0), // #E8E0F0 light lavender
]
guard let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: gradientColors as CFArray,
    locations: [0.0, 1.0]
) else {
    fatalError("Failed to create gradient")
}

// NSView coordinates: origin at bottom-left, so top = size, bottom = 0
// Dark at top, light at bottom
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: size / 2, y: size),  // top: dark
    end: CGPoint(x: size / 2, y: 0),       // bottom: light
    options: []
)

// Draw text using NSAttributedString
func drawCenteredText(_ text: String, fontSize: CGFloat, weight: NSFont.Weight, centerY: CGFloat) {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let textSize = string.size()
    let x = (size - textSize.width) / 2
    let y = size - centerY - textSize.height / 2  // convert from top-down to bottom-up
    string.draw(at: NSPoint(x: x, y: y))
}

// ".md" — large, bold, upper area
drawCenteredText(".md", fontSize: 340, weight: .bold, centerY: 370)

// "QuickLook" — smaller, regular, lower area
drawCenteredText("QuickLook", fontSize: 120, weight: .regular, centerY: 660)

image.unlockFocus()

// Save as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Failed to create PNG data")
}

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let rootDir = scriptDir.deletingLastPathComponent()
let outputPath = rootDir
    .appendingPathComponent("MarkdownQuickLookApp")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")
    .appendingPathComponent("icon_1024x1024.png")

try pngData.write(to: outputPath)
print("Icon generated: \(outputPath.path)")
