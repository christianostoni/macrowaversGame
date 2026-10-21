// Renders an Icon Composer document's layers into visionOS image-stack layers (1024 x 1024 px): Xcode compiles
// .icon documents for iOS, macOS and watchOS only. The dragon (GroupFG) is the front layer, the orange, its shine
// and the leaf the middle one, an opaque light fill the back one. The whole drawing shrinks to fit the round mask.
// Usage: swift Assets/Icon/make_visionos_icon.swift Assets/Icon/AppIcon.icon <output dir> [fit radius px]
// then copy Front.png, Middle.png and Back.png into Sources/Macrowavers/Resources/Assets.xcassets/
// AppIcon.solidimagestack/<Layer>.solidimagestacklayer/Content.imageset/ (preview-visionOS.png is a flat preview).
import AppKit

let args = CommandLine.arguments
let doc = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let fitRadius = args.count > 3 ? CGFloat(Double(args[3])!) : 470
let side = 1024
let center = CGPoint(x: 512, y: 512)

struct Layer { let image: NSImage; let scale: CGFloat; let dx: CGFloat; let dy: CGFloat; let name: String }

let json = try JSONSerialization.jsonObject(with: Data(contentsOf: doc.appendingPathComponent("icon.json"))) as! [String: Any]
let group = (json["groups"] as! [[String: Any]])[0]
// First listed = frontmost.
let layers: [Layer] = (group["layers"] as! [[String: Any]]).map { entry in
    let name = entry["image-name"] as! String
    let position = entry["position"] as! [String: Any]
    let translation = position["translation-in-points"] as! [Double]
    let image = NSImage(contentsOf: doc.appendingPathComponent("Assets/\(name)"))!
    if let bitmap = image.representations.first as? NSBitmapImageRep {
        image.size = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)   // PNG pixels = points
    }
    return Layer(image: image, scale: position["scale"] as! Double, dx: translation[0], dy: translation[1], name: name)
}

func context() -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Draws layers back to front; `fit` shrinks the whole composition around the centre.
func render(_ selected: [Layer], fit: CGFloat) -> CGContext {
    let ctx = context()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    for layer in selected.reversed() {
        let w = layer.image.size.width * layer.scale * fit
        let h = layer.image.size.height * layer.scale * fit
        // Icon Composer: y grows downwards; CoreGraphics: upwards.
        let cx = center.x + layer.dx * fit
        let cy = center.y - layer.dy * fit
        layer.image.draw(in: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    return ctx
}

/// Farthest visible pixel from the centre.
func maxRadius(_ ctx: CGContext) -> CGFloat {
    let data = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * side)
    var best: CGFloat = 0
    for y in 0..<side {
        for x in 0..<side where data[y * ctx.bytesPerRow + x * 4 + 3] > 16 {
            best = max(best, hypot(CGFloat(x) + 0.5 - center.x, CGFloat(y) + 0.5 - center.y))
        }
    }
    return best
}

func save(_ ctx: CGContext, _ file: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(file))
}

let front = layers.filter { $0.name.hasPrefix("GroupFG") }
let middle = layers.filter { !$0.name.hasPrefix("GroupFG") }
let radius = maxRadius(render(layers, fit: 1))
let fit = min(1, fitRadius / radius)
print("farthest pixel \(Int(radius)) px from the centre, fit \(String(format: "%.3f", fit))")

save(render(front, fit: fit), "Front.png")
save(render(middle, fit: fit), "Middle.png")

// Back: opaque, Icon Composer's automatic light fill (white to light grey).
let back = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                   CGColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1)] as CFArray,
                          locations: [0, 1])!
back.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
save(back, "Back.png")

// Preview: the three layers flattened and masked to the visionOS circle.
let preview = context()
preview.addEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
preview.clip()
for file in ["Back.png", "Middle.png", "Front.png"] {
    let image = NSImage(contentsOf: out.appendingPathComponent(file))!
    preview.draw(image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(x: 0, y: 0, width: side, height: side))
}
save(preview, "preview-visionOS.png")
