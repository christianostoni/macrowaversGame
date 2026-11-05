import CoreGraphics
import RealityKit
import UIKit

/// Soft glows drawn in code, white with premultiplied alpha so a material's tint gives their colour (like the orbs'
/// halo, `OrbSceneBuilder`): a thin ring of light under a fruit.
enum GlowTexture {
    /// A thin ring of light at `radius` (a share of the square's half width), `width` its line's half width, with a
    /// faint glow on both sides of it.
    @MainActor
    static func ring(radius: Float, width: Float) async -> TextureResource? {
        await make(size: 512) { distance in
            let off = abs(distance - radius)
            let line = min(max((width - off) / (width * 0.5), 0), 1)
            let glow = 0.35 * exp(-off * off / (width * width * 18))
            return min(line + glow, 1)
        }
    }

    /// A square texture whose alpha at each pixel is `alpha(distance from the centre, 0...1 at the half width)`.
    @MainActor
    private static func make(size: Int, alpha: (Float) -> Float) async -> TextureResource? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let half = Float(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5 - half) / half
                let dy = (Float(y) + 0.5 - half) / half
                let value = UInt8(max(0, min(alpha((dx * dx + dy * dy).squareRoot()), 1)) * 255 + 0.5)
                let index = (y * size + x) * 4
                // White, premultiplied: every channel is the alpha.
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
                pixels[index + 3] = value
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        return try? await TextureResource(image: image, options: .init(semantic: .color))
    }

    /// An unlit, see-through material showing `texture` tinted `colour` (writes no depth: its square's clear corners
    /// would hide what is behind them).
    @MainActor
    static func material(_ texture: TextureResource, colour: UIColor, opacity: Float = 1) -> UnlitMaterial {
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: colour, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.writesDepth = false
        material.faceCulling = .none
        return material
    }
}
