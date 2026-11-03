// Draws the app icon as a 1024 px PNG. Run: swift make_icon.swift out.png [logo.png]
// Default: the Caddy logo on a plain white rounded square. Set blueTile to true for the old soft blue tile.
import AppKit

let blueTile = false

let size: CGFloat = 1024
let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "icon_1024.png"
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let poses = here.deletingLastPathComponent().appendingPathComponent("mascot/poses_ai")

/// The blue tile needs the see-through cutout. The white square takes the logo as drawn,
/// the 1024 px one when it exists, else the small one.
func defaultLogo() -> String {
    if blueTile { return here.appendingPathComponent("caddy_logo_1024.png").path }
    let big = poses.appendingPathComponent("logo_neutral_1024.png").path
    return FileManager.default.fileExists(atPath: big) ? big : poses.appendingPathComponent("logo_neutral.png").path
}
let logoPath = args.count > 2 ? args[2] : defaultLogo()

guard let logoData = NSImage(contentsOfFile: logoPath),
      let logo = logoData.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("Could not read the logo at \(logoPath)\n".data(using: .utf8)!)
    exit(1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, a])!
}

/// The logo's own corner colour when it is solid, so its near-white backdrop meets the square with no seam.
func paper() -> CGColor {
    guard let c = NSBitmapImageRep(cgImage: logo).colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB),
          c.alphaComponent > 0.99 else { return rgb(0xFFFFFF) }
    return CGColor(colorSpace: space, components: [c.redComponent, c.greenComponent, c.blueComponent, 1])!
}

// macOS icon grid: 824 pt body centred on a 1024 canvas, about 185 pt corner radius.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Soft blue is close to the goggles. White keeps the logo as the only colour.
ctx.addPath(bodyPath); ctx.setFillColor(blueTile ? rgb(0xBFE0F7) : paper()); ctx.fillPath()
if !blueTile {
    // A faint edge so the white square still shows on a white desktop or Finder window.
    ctx.addPath(bodyPath); ctx.setStrokeColor(rgb(0x000000, 0.10)); ctx.setLineWidth(4); ctx.strokePath()
}

// The chick, centred and large. A little low, so the head tuft has room. Clipped to the square.
let side: CGFloat = blueTile ? 680 : 880
ctx.addPath(bodyPath); ctx.clip()
ctx.draw(logo, in: CGRect(x: (size - side) / 2, y: (size - side) / 2 - 10, width: side, height: side))

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
