import SwiftUI
import UIKit

/// The game's loading animation, in place of the system spinner wherever the game loads (the launch window while the
/// island is built, the ride's space while the sky is built): the stone dragon tangling into the puzzle's knot and
/// untangling into a ring, turning once around, flat like a 2D drawing. Blender renders it from the game's own dragon
/// (`Assets/Blender/loading-dragon/make_loading_animation.py`) into one sprite sheet, `DragonLoading.png`: `columns`
/// frames a row, left to right then top to bottom, played at `framesPerSecond`.
///
/// The sheet is decoded once, off the main thread, and cut into frames that share its pixels (~10 MB); until then,
/// or without the file, the system spinner turns. With Reduce Motion on, the dragon rests in its ring.
struct DragonLoadingView: View {
    /// The sheet's layout and rate: the script's `FRAMES`, `COLUMNS` and `FPS`.
    static let frameCount = 72
    static let columns = 9
    static let framesPerSecond: Double = 24
    /// The frame shown with Reduce Motion: the dragon untangled, in its ring.
    static let restingFrame = 40
    static let resourceName = "DragonLoading"

    /// Width and height (pt).
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [CGImage]?

    var body: some View {
        Group {
            if let frames, !frames.isEmpty {
                if reduceMotion {
                    frame(frames[min(Self.restingFrame, frames.count - 1)])
                } else {
                    TimelineView(.animation(minimumInterval: 1 / Self.framesPerSecond)) { context in
                        let tick = Int(context.date.timeIntervalSinceReferenceDate * Self.framesPerSecond)
                        frame(frames[tick % frames.count])
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .frame(width: size, height: size)
        .task { frames = await Self.loadFrames() }
        .accessibilityLabel("Loading")
    }

    private func frame(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }

    // MARK: - Frames

    /// The frames, cut once and kept for every loading screen after the first.
    @MainActor private static var cachedFrames: [CGImage]?

    @MainActor
    private static func loadFrames() async -> [CGImage]? {
        if let cachedFrames { return cachedFrames }
        let frames = await Task.detached(priority: .userInitiated) { cutFrames() }.value
        cachedFrames = frames
        return frames
    }

    /// Decodes the sheet into one bitmap (drawn as it is, its frames would each decode the whole PNG every time they
    /// are shown) and cuts it into `frameCount` frames. Nil without the file.
    private nonisolated static func cutFrames() -> [CGImage]? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let source = UIImage(contentsOfFile: url.path)?.cgImage,
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("⚠️ DragonLoading.png not found: the system spinner turns instead")
            return nil
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let sheet = context.makeImage() else { return nil }
        let side = sheet.width / columns
        return (0..<frameCount).compactMap { index in
            let (row, column) = index.quotientAndRemainder(dividingBy: columns)
            return sheet.cropping(to: CGRect(x: column * side, y: row * side, width: side, height: side))
        }
    }
}

#Preview {
    DragonLoadingView()
        .padding()
        .glassBackgroundEffect()
}
