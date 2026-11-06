#if os(visionOS)
import SwiftUI

/// The feast's icons in the game's style, like the life flask (`LifeFlaskView`): a lilac rim, a violet band inside
/// it, a gradient in the game's colours, a glint of light and a speck of gold.
@MainActor
enum GameIcon {
    static var rim: Color { LifeFlaskView.rimLight }
    static var band: Color { LifeFlaskView.rim }

    /// `shape` drawn in the game's style, filled with `colours` (top to bottom).
    @ViewBuilder
    static func styled(_ shape: some Shape, colours: [Color], size: CGFloat) -> some View {
        ZStack {
            shape.stroke(rim, style: StrokeStyle(lineWidth: size * 0.12, lineJoin: .round))
            shape.fill(LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom))
            shape.stroke(band, style: StrokeStyle(lineWidth: size * 0.045, lineJoin: .round))
        }
    }
}

/// The breath of fire: a flame, orange to gold with a golden heart while the fire is ready; a dark violet ember
/// while it recharges.
struct FlameIcon: View {
    let isLit: Bool
    let size: CGFloat

    var body: some View {
        let colours = isLit
            ? [LifeFlaskView.colour(RidePalette.red), LifeFlaskView.colour(RidePalette.orange),
               LifeFlaskView.gold]
            : [LifeFlaskView.colour(RidePalette.slate), LifeFlaskView.colour(RidePalette.violet)]
        ZStack {
            GameIcon.styled(IconFlameShape(), colours: colours, size: size)
            // Its heart, gold, low in the flame.
            IconFlameShape()
                .fill(isLit ? LifeFlaskView.paleGold : LifeFlaskView.colour(RidePalette.lilac).opacity(0.4))
                .frame(width: size * 0.38, height: size * 0.46)
                .offset(y: size * 0.18)
            Glint(size: size)
                .offset(x: -size * 0.14, y: -size * 0.02)
        }
        .frame(width: size * 0.78, height: size)
        .shadow(color: isLit ? LifeFlaskView.paleGold.opacity(0.6) : .clear, radius: size * 0.08)
    }
}

/// The fruit eaten: an apple, the apple's red to the pomegranate's pink, a teal stem and a lime leaf.
struct AppleIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // The leaf and the stem behind the apple's top.
            IconLeafShape()
                .fill(LinearGradient(colors: [LifeFlaskView.colour(RidePalette.lime),
                                              LifeFlaskView.colour(RidePalette.teal)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
                .overlay(IconLeafShape().stroke(GameIcon.band, lineWidth: size * 0.035))
                .frame(width: size * 0.36, height: size * 0.2)
                .rotationEffect(.degrees(-28))
                .offset(x: size * 0.16, y: -size * 0.38)
            Capsule()
                .fill(GameIcon.band)
                .frame(width: size * 0.07, height: size * 0.22)
                .rotationEffect(.degrees(12))
                .offset(x: size * 0.02, y: -size * 0.36)
            GameIcon.styled(IconAppleShape(),
                            colours: [LifeFlaskView.colour(RidePalette.red), LifeFlaskView.colour(RidePalette.pink)],
                            size: size)
                .frame(width: size * 0.9, height: size * 0.8)
                .offset(y: size * 0.08)
            Glint(size: size)
                .offset(x: -size * 0.2, y: -size * 0.02)
            Circle()
                .fill(LifeFlaskView.paleGold)
                .frame(width: size * 0.06, height: size * 0.06)
                .offset(x: size * 0.18, y: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

/// Light on the glass: a short curved stroke.
private struct Glint: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0.52, to: 0.68)
            .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
            .frame(width: size * 0.5, height: size * 0.5)
    }
}

/// A flame: round at its foot, pointed at its tip, leaning a little.
struct IconFlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width,
                                                                    y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: point(0.5, 1))
        path.addCurve(to: point(0.08, 0.62), control1: point(0.22, 1), control2: point(0.06, 0.82))
        path.addCurve(to: point(0.46, 0), control1: point(0.12, 0.38), control2: point(0.44, 0.24))
        path.addCurve(to: point(0.92, 0.62), control1: point(0.6, 0.26), control2: point(0.94, 0.38))
        path.addCurve(to: point(0.5, 1), control1: point(0.9, 0.84), control2: point(0.76, 1))
        path.closeSubpath()
        return path
    }
}

/// An apple's body: two round shoulders with a dip between them, a round bottom.
struct IconAppleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width,
                                                                    y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: point(0.5, 0.16))
        path.addCurve(to: point(0.03, 0.42), control1: point(0.3, 0), control2: point(0.02, 0.06))
        path.addCurve(to: point(0.5, 1), control1: point(0.04, 0.8), control2: point(0.3, 1.04))
        path.addCurve(to: point(0.97, 0.42), control1: point(0.7, 1.04), control2: point(0.96, 0.8))
        path.addCurve(to: point(0.5, 0.16), control1: point(0.98, 0.06), control2: point(0.7, 0))
        path.closeSubpath()
        return path
    }
}

/// A leaf: pointed at both ends.
struct IconLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        let bulge = rect.height * 0.4
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.minY - bulge))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.maxY + bulge))
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 32) {
        FlameIcon(isLit: true, size: 85)
        FlameIcon(isLit: false, size: 85)
        AppleIcon(size: 85)
    }
    .padding()
    .background(.black)
}
#endif
