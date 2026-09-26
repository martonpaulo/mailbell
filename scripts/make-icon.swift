#!/usr/bin/env swift
// Draws the Mailbell app icon: a white outlined bell on the amber macOS plate. Every icon
// Mailbell ships comes from this file; `make icon` runs it and the generators that read
// its output. From the repository root:
//   scripts/make-icon.swift <output-dir>
//     writes <output-dir>/AppIcon.iconset; then
//     iconutil -c icns <output-dir>/AppIcon.iconset -o Support/AppIcon.icns
//   scripts/make-icon.swift --favicon <site-dir>
//     writes <site-dir>/favicon.ico (16, 32 and 48 px PNG entries), favicon-192.png,
//     apple-touch-icon.png and the page's app icon, assets/app-icon-280.webp (needs cwebp).
import AppKit

/// AppKit returns nil here only when it cannot allocate the object; stop with its name.
func required<T>(_ value: T?, _ what: String) -> T {
    guard let value else { fatalError("could not create \(what)") }
    return value
}

func color(_ hex: Int) -> NSColor {
    NSColor(deviceRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1)
}

/// The Big Sur-style plate on the 1024 grid: 824 units with a 100-unit margin, as in
/// Apple's macOS app icon template.
let plateRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let plateRadius: CGFloat = 185
let plateTop = color(0xfdd34a)
let plateBottom = color(0xd89e00)

/// How the bell sits on the plate at one pixel size.
struct Rendition {
    /// The side of the bell's 24-unit box, in 1024-grid units. The owner's canvas draws
    /// a 36 px bell on a 64 px plate, so the box is 36/64 of the 824-unit plate.
    var bellBox: CGFloat = 824 * 36 / 64
    /// Line width in the bell's 24-unit grid. 2 is Lucide's own stroke.
    var stroke: CGFloat = 2

    /// A 2-unit line on a 16 or 32 px icon is under one pixel wide and breaks up, so the
    /// small sizes draw a larger bell with a heavier line.
    static func forPixels(_ pixels: Int) -> Rendition {
        switch pixels {
        case ...16: Rendition(bellBox: 600, stroke: 3.6)
        case ...32: Rendition(bellBox: 540, stroke: 2.8)
        case ...48: Rendition(bellBox: 500, stroke: 2.4)
        default: Rendition()
        }
    }
}

/// Lucide's `bell` (ISC License, see NOTICE.md) in its 24-unit grid, y pointing up:
/// the dome `M6 8a6 6 0 0 1 12 0`, the flanks `c0 7 3 9 3 9` and `s3-2 3-9`, the rim
/// `H3`, and the clapper `M10.3 21a1.94 1.94 0 0 0 3.4 0`. SVG y becomes 24 - y.
func bellPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 6, y: 16))
    path.appendArc(withCenter: NSPoint(x: 12, y: 16), radius: 6,
                   startAngle: 180, endAngle: 0, clockwise: true)
    path.curve(to: NSPoint(x: 21, y: 7),
               controlPoint1: NSPoint(x: 18, y: 9), controlPoint2: NSPoint(x: 21, y: 7))
    path.line(to: NSPoint(x: 3, y: 7))
    path.curve(to: NSPoint(x: 6, y: 16),
               controlPoint1: NSPoint(x: 3, y: 7), controlPoint2: NSPoint(x: 6, y: 9))
    path.close()

    // The clapper is the short arc of a 1.94-unit circle through (10.3, 3) and (13.7, 3),
    // hanging below the chord.
    let radius: CGFloat = 1.94
    let halfChord: CGFloat = 1.7
    let center = NSPoint(x: 12, y: 3 + (radius * radius - halfChord * halfChord).squareRoot())
    let angle = atan2(3 - center.y, halfChord) * 180 / .pi
    path.move(to: NSPoint(x: 12 - halfChord, y: 3))
    path.appendArc(withCenter: center, radius: radius,
                   startAngle: 180 - angle, endAngle: 360 + angle, clockwise: false)
    return path
}

/// Draws the plate and the bell on the 1024 grid, in the caller's transform.
func drawIcon(_ rendition: Rendition) {
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: plateRadius, yRadius: plateRadius)
    required(NSGradient(starting: plateBottom, ending: plateTop), "the plate gradient")
        .draw(in: plate, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: plateRect.midX - rendition.bellBox / 2,
                         yBy: plateRect.midY - rendition.bellBox / 2)
    transform.scale(by: rendition.bellBox / 24)
    transform.concat()
    let bell = bellPath()
    bell.lineWidth = rendition.stroke
    bell.lineCapStyle = .round
    bell.lineJoinStyle = .round
    NSColor.white.setStroke()
    bell.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

/// A `pixels`-square bitmap with the 1024 grid mapped onto `grid` (the whole grid by
/// default) and `draw` run inside it.
func render(pixels: Int, grid: NSRect = NSRect(x: 0, y: 0, width: 1024, height: 1024),
            inset: CGFloat = 0, background: NSColor? = nil, draw: () -> Void) -> NSBitmapImageRep {
    let rep = required(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                       "a \(pixels) px bitmap")
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    if let background {
        background.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    }
    let transform = NSAffineTransform()
    transform.translateX(by: inset, yBy: inset)
    transform.scale(by: (CGFloat(pixels) - 2 * inset) / grid.width)
    transform.translateX(by: -grid.minX, yBy: -grid.minY)
    transform.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func pngData(_ rep: NSBitmapImageRep) -> Data {
    required(rep.representation(using: .png, properties: [:]), "PNG data")
}

// The favicon is the plate without the app icon's 100-unit margin, which is for the Dock
// and would shrink a 16 px tab icon further. The plate edge stays on whole pixels.
enum Favicon {
    static let insetFraction: CGFloat = 0.02
    static let icoSizes = [16, 32, 48]
    /// Google Search asks for a square favicon larger than 48 px; 192 is 4 x 48.
    static let largeSize = 192
}

func drawFavicon(pixels: Int) -> NSBitmapImageRep {
    render(pixels: pixels, grid: plateRect,
           inset: (CGFloat(pixels) * Favicon.insetFraction).rounded(.down)) {
        drawIcon(Rendition.forPixels(pixels))
    }
}

/// An ICO file whose entries are PNG images, which every current browser and Google
/// Search read: a 6-byte header, one 16-byte directory entry per image, then the data.
/// https://learn.microsoft.com/en-us/previous-versions/ms997538(v=msdn.10)
func icoData(_ images: [(pixels: Int, png: Data)]) -> Data {
    var data = Data()
    func append16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8 & 0xff)]) }
    func append32(_ value: Int) { append16(value & 0xffff); append16(value >> 16 & 0xffff) }
    append16(0)                 // reserved
    append16(1)                 // type: icon
    append16(images.count)
    var offset = 6 + 16 * images.count
    for image in images {
        let side = UInt8(image.pixels >= 256 ? 0 : image.pixels)  // 0 means 256
        data.append(contentsOf: [side, side, 0, 0])  // width, height, palette, reserved
        append16(1)             // colour planes
        append16(32)            // bits per pixel
        append32(image.png.count)
        append32(offset)
        offset += image.png.count
    }
    for image in images { data.append(image.png) }
    return data
}

/// cwebp writes the page's WebP copy of the icon; AppKit cannot encode WebP.
func writeWebP(_ png: Data, to destination: URL) throws {
    let source = FileManager.default.temporaryDirectory
        .appendingPathComponent("mailbell-icon-\(ProcessInfo.processInfo.processIdentifier).png")
    try png.write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["cwebp", "-quiet", "-lossless", "-exact", "-z", "9", "-metadata", "none",
                         source.path, "-o", destination.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        FileHandle.standardError.write(Data("error: cwebp failed; it is required (brew install webp)\n".utf8))
        exit(1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--favicon" {
    let dir = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "site")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("assets"),
                                            withIntermediateDirectories: true)
    let entries = Favicon.icoSizes.map { (pixels: $0, png: pngData(drawFavicon(pixels: $0))) }
    try icoData(entries).write(to: dir.appendingPathComponent("favicon.ico"))
    try pngData(drawFavicon(pixels: Favicon.largeSize))
        .write(to: dir.appendingPathComponent("favicon-\(Favicon.largeSize).png"))
    // The page shows the icon at up to 140 CSS px, so 280 px covers a 2x display. The Apple
    // touch icon is opaque because iOS fills transparency with black.
    try writeWebP(pngData(render(pixels: 280) { drawIcon(Rendition()) }),
                  to: dir.appendingPathComponent("assets/app-icon-280.webp"))
    try pngData(render(pixels: 180, background: .white) { drawIcon(Rendition()) })
        .write(to: dir.appendingPathComponent("apple-touch-icon.png"))
    print("wrote \(dir.path)/favicon.ico, favicon-\(Favicon.largeSize).png, apple-touch-icon.png and assets/app-icon-280.webp")
} else {
    let outputDir = arguments.first ?? "artifacts/icon"
    let iconsetURL = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconsetURL)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for (scale, suffix) in [(1, ""), (2, "@2x")] {
            let pixels = size * scale
            try pngData(render(pixels: pixels) { drawIcon(Rendition.forPixels(pixels)) })
                .write(to: iconsetURL.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
    print("wrote \(iconsetURL.path)")
}
