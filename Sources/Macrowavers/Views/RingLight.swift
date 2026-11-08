import SwiftUI

/// A ring light round a button's or a panel's edge (Start, the scroll's Continue and Skip, the elixir's label), in the
/// colours of the game's name (`ToranjTitleView`, `ToranjSkin.metal`: the pomegranate's skin, the fruits' leaf):
/// a soft glow round the outside of the edge, only while the player looks at it, its colours going round (no sharp
/// line on the edge: it read as a bright stroke down one side). Where the eyes are is private, so the system runs it
/// (hover effects, grouped with the view's own); with Reduce Motion it only lights up.
struct RingLight: ViewModifier {
    /// The edge it runs round: a capsule for a button, the panel's own rounded rectangle.
    let shape: AnyShape
    /// How far the edge lies outside the view it is on: a button's glass reaches past its label by the button's own
    /// padding. On the label, the glow is pressed in with the button when it is pinched; round the button it stayed
    /// put and a gap opened between it and the glass.
    var outset = CGSize.zero

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
                        // The glow: a soft blurred band, only while looked at, and only outside the edge: inside, it
                        // showed through the button's glass as a coloured line.
                        ring(in: proxy.size, lineWidth: 6)
                            .blur(radius: 6)
                            .mask { outside }
                            .hoverEffect { effect, isActive, _ in
                                effect.animation(.easeInOut(duration: 0.4)) { $0.opacity(isActive ? 0.7 : 0) }
                            }
                    }
                }
                .padding(.horizontal, -outset.width)
                .padding(.vertical, -outset.height)
                .allowsHitTesting(false)
            }
            .hoverEffectGroup()
    }

    /// Everything round the shape, with room for the glow, but not the shape itself.
    private var outside: some View {
        Rectangle()
            .padding(-24)
            .overlay { shape.blendMode(.destinationOut) }
            .compositingGroup()
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

    /// `RingLight` round the capsule of the button whose label this is, `controlSize` large or small (their padding
    /// round the label, measured on visionOS 26).
    func ringLight(aroundButtonOf controlSize: ControlSize) -> some View {
        let outset = controlSize == .small ? CGSize(width: 12, height: 6) : CGSize(width: 20, height: 13.5)
        return modifier(RingLight(shape: AnyShape(Capsule()), outset: outset))
    }
}
