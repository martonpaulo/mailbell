#!/usr/bin/env swift
// Renders the DMG installer background (Support/MailbellInstallerBackground.tiff, 1x + 2x) that
// scripts/make-dmg.sh lays out. The distinctive basename keeps Finder from reusing cached artwork
// from an older mounted Mailbell volume. From the repository root:
//   scripts/render-dmg-background.swift && tiffutil -cathidpicheck \
//     artifacts/dmg-bg.png artifacts/dmg-bg@2x.png \
//     -out Support/MailbellInstallerBackground.tiff
// The geometry must stay in sync with make-dmg.sh's defaults: window 680x400, 112 pt icons, the
// app centered at (180, 225) and Applications at (500, 225), measured from the top left.
import AppKit

/// AppKit returns nil here only when it cannot allocate the object; stop with its name.
func required<T>(_ value: T?, _ what: String) -> T {
    guard let value else { fatalError("could not create \(what)") }
    return value
}

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

let size = NSSize(width: 680, height: 400)
let iconSize: CGFloat = 112
let appCenterX: CGFloat = 180
let applicationsCenterX: CGFloat = 500
// Finder measures from the top; AppKit draws from the bottom.
let iconRowY = size.height - 225
let installerIcon = NSImage(contentsOfFile: "Support/AppInstallerIcon.icns")

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let rep = required(NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: Int(size.width * scale),
                                        pixelsHigh: Int(size.height * scale),
                                        bitsPerSample: 8, samplesPerPixel: 4,
                                        hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
                       "a bitmap at scale \(scale)")
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.setShouldAntialias(true)

    let bounds = NSRect(origin: .zero, size: size)
    required(NSGradient(colors: [color(0xFFF8D7), color(0xFFE5A1), color(0xBFE9F3)]),
             "the background gradient")
        .draw(in: bounds, angle: -35)

    // The bell, large and faint in the corner, as a watermark behind the card.
    installerIcon?.draw(in: NSRect(x: -70, y: -110, width: 330, height: 330),
                        from: .zero, operation: .sourceOver, fraction: 0.10)

    // A card behind both icons and their labels, so the drop target reads as one row.
    let card = NSRect(x: 48, y: iconRowY - 110, width: size.width - 96, height: 196)
    let shadow = NSShadow()
    shadow.shadowColor = color(0x5F4E1E, alpha: 0.18)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -7)
    shadow.set()
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16)
    color(0xFFFDF4).setFill()
    cardPath.fill()
    NSShadow().set()
    color(0xFFFFFF, alpha: 0.70).setStroke()
    cardPath.lineWidth = 1
    cardPath.stroke()

    let arrowColor = color(0xD89B00)
    arrowColor.setStroke()
    let arrowStartX = appCenterX + iconSize / 2 + 26
    let arrowEndX = applicationsCenterX - iconSize / 2 - 26
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: arrowStartX, y: iconRowY))
    arrow.line(to: NSPoint(x: arrowEndX, y: iconRowY))
    arrow.move(to: NSPoint(x: arrowEndX - 18, y: iconRowY + 18))
    arrow.line(to: NSPoint(x: arrowEndX, y: iconRowY))
    arrow.line(to: NSPoint(x: arrowEndX - 18, y: iconRowY - 18))
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = "Drag Mailbell to Applications" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .bold),
        .foregroundColor: color(0x2B2517),
        .paragraphStyle: paragraph
    ]
    let titleHeight = title.size(withAttributes: attributes).height
    title.draw(in: NSRect(x: 0, y: size.height - 64 - titleHeight / 2, width: size.width, height: titleHeight),
               withAttributes: attributes)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard installerIcon != nil else {
    FileHandle.standardError.write(Data("error: run from the repository root; Support/AppInstallerIcon.icns not found\n".utf8))
    exit(1)
}
let outputDirectory = "artifacts"
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
for (scale, name) in [(CGFloat(1), "dmg-bg.png"), (2, "dmg-bg@2x.png")] {
    let rep = draw(scale: scale)
    try required(rep.representation(using: .png, properties: [:]), "PNG data")
        .write(to: URL(fileURLWithPath: "\(outputDirectory)/\(name)"))
    print("wrote \(outputDirectory)/\(name)")
}
