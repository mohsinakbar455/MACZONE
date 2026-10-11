// Geometric MACZONE identity: three native window zones, drawn at every icon size.
import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    // Exact BrandMark proportions, with standard icon padding. AppKit's
    // coordinates run bottom-up, while the SwiftUI mark runs top-down.
    let w = s * 0.88, inset = s * 0.06
    NSColor(srgbRed: 1, green: 225/255, blue: 79/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: inset, y: inset, width: w, height: w), xRadius: w*0.23, yRadius: w*0.23).fill()
    NSColor(srgbRed: 23/255, green: 23/255, blue: 23/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: inset+w*0.18, y: inset+w*0.20, width: w*0.27, height: w*0.60), xRadius: w*0.045, yRadius: w*0.045).fill()
    NSBezierPath(roundedRect: CGRect(x: inset+w*0.53, y: inset+w*0.535, width: w*0.29, height: w*0.265), xRadius: w*0.045, yRadius: w*0.045).fill()
    NSColor(srgbRed: 25/255, green: 40/255, blue: 83/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: inset+w*0.53, y: inset+w*0.20, width: w*0.29, height: w*0.265), xRadius: w*0.045, yRadius: w*0.045).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try data.write(to: directory.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
