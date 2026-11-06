import SwiftUI

/// A ring light round a button's or a panel's edge (Start, the scroll's Continue and Skip, the elixir's label), in the
/// colours of the game's name (`ToranjTitleView`, `ToranjSkin.metal`: the pomegranate's skin, the fruits' leaf):
/// dim and still, it lights up and its colours go round the edge while the player looks at it. Where the eyes are is
/// private, so the system runs it (hover effects, grouped with the view's own); with Reduce Motion it only lights up.
struct RingLight: ViewModifier {
    /// The edge it runs round: a capsule for a button, the panel's own rounded rectangle.
    let shape: AnyShape

    private static let colors = [
        // Mostly the pomegranate's pinks (its `Airbrush_Skin` stops, in sRGB), a touch of its crimson and the
        // leaf's lime rim.
        Color(red: 0.90, green: 0.65, blue: 0.90), // pink rim
        Color(red: 0.67, green: 0.45, blue: 0.62), // mauve
        Color(red: 0.64, green: 0.24, blue: 0.34).opacity(0.8), // crimson
        Color(red: 0.67, green: 0.45, blue: 0.62),
        Color(red: 0.86, green: 0.96, blue: 0.63).opacity(0.6), // leaf's lime rim
        Color(red: 0.90, green: 0.65, blue: 0.90),
    ]
    /// Once round every 8 s while looked at: a long animation, far longer than any look.
    private static let laps = 60.0
    private static let lapDuration = 8.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    ZStack {
                        // The glow: a soft blurred band, only while looked at.
                        ring(in: proxy.size, lineWidth: 6)
                            .blur(radius: 6)
                            .hoverEffect { effect, isActive, _ in
                                effect.animation(.easeInOut(duration: 0.4)) { $0.opacity(isActive ? 0.55 : 0) }
                            }
                        ring(in: proxy.size, lineWidth: 1.5)
                            .hoverEffect { effect, isActive, _ in
                                effect.animation(.easeInOut(duration: 0.4)) { $0.opacity(isActive ? 0.85 : 0.35) }
                            }
                    }
                }
                .allowsHitTesting(false)
            }
            .hoverEffectGroup()
    }

    /// The colours on a square wide enough to cover the edge whichever way it turns, seen through it.
    private func ring(in size: CGSize, lineWidth: CGFloat) -> some View {
        let side = hypot(size.width, size.height)
        return AngularGradient(colors: Self.colors, center: .center)
            .frame(width: side, height: side)
            .hoverEffect { effect, isActive, _ in
                effect.animation(isActive ? .linear(duration: Self.laps * Self.lapDuration) : .easeOut(duration: 0.6)) {
                    $0.rotationEffect(.degrees(isActive && !reduceMotion ? Self.laps * 360 : 0))
                }
            }
            .frame(width: size.width, height: size.height)
            .mask { shape.stroke(lineWidth: lineWidth) }
    }
}

extension View {
    /// `RingLight` round `shape` (a capsule: a button's).
    func ringLight(in shape: some Shape = Capsule()) -> some View { modifier(RingLight(shape: AnyShape(shape))) }
}
