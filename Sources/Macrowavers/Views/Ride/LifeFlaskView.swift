#if os(visionOS)
import SwiftUI

/// The dragon's life during the feast, as a glass flask lying on its side (like the elixir's, in the game's colours):
/// a round bulb on the left with a Persian eight-pointed star in it, standing on a little flared foot, and a long
/// tube holding the life, one stretch a heart, notched between them. The liquid shimmers with specks of gold and its
/// front waves; it drains a stretch with each poisoned fruit and the bulb goes dark when none is left.
struct LifeFlaskView: View {
    let hearts: Int
    let maxHearts: Int

    /// The flask's size (points): long and low.
    static let size = CGSize(width: 460, height: 92)
    /// The bulb's size (points): the icons beside the flask are as big.
    static var bulbDiameter: CGFloat { FlaskGeometry(size: size).bulbRadius * 2 }
    /// The game's colours: the petals' violet glass and its lilac rim, the pomegranate's pink and the apple's red in
    /// the liquid, the flowers' gold in the star and the specks.
    static let rim = colour(RidePalette.violet)
    static let rimLight = colour(RidePalette.lilac)
    static let glass = colour(RidePalette.night).opacity(0.75)
    static let liquid = [colour(RidePalette.red), colour(RidePalette.pink)]
    static let gold = colour(RidePalette.gold)
    static let paleGold = colour(RidePalette.paleGold)
    /// Specks of gold in the liquid.
    static let speckCount = 14

    private var level: Double { maxHearts > 0 ? Double(hearts) / Double(maxHearts) : 0 }

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let shape = FlaskGeometry(size: Self.size)
            ZStack(alignment: .topLeading) {
                // The glass: a lilac rim, a violet band inside it, the dark of the night through it.
                FlaskShape(geometry: shape, inset: 0).fill(Self.rimLight)
                FlaskShape(geometry: shape, inset: 3).fill(Self.rim)
                FlaskShape(geometry: shape, inset: 9).fill(Self.glass)

                // The liquid, its front waving, with the gold specks in it.
                ZStack(alignment: .topLeading) {
                    LiquidShape(geometry: shape, level: level, phase: time * 3)
                        .fill(LinearGradient(colors: Self.liquid, startPoint: .leading, endPoint: .trailing))
                    ForEach(0..<Self.speckCount, id: \.self) { index in
                        speck(index, time: time, geometry: shape)
                    }
                    .mask(LiquidShape(geometry: shape, level: level, phase: time * 3))
                }
                .mask(FlaskShape(geometry: shape, inset: 9))
                .animation(.spring(duration: 0.8), value: level)

                // A notch between every two hearts.
                ForEach(1..<max(maxHearts, 1), id: \.self) { index in
                    let x = shape.tube.minX + shape.tube.width * CGFloat(index) / CGFloat(maxHearts)
                    Capsule()
                        .fill(Self.rim.opacity(0.9))
                        .frame(width: 4, height: shape.tube.height * 0.5)
                        .position(x: x, y: shape.tube.minY + shape.tube.height * 0.25)
                }

                // The star in the bulb, lit while the dragon has life.
                EightPointedStar()
                    .fill(hearts > 0 ? Self.gold : Self.rim)
                    .frame(width: shape.bulbRadius * 1.1, height: shape.bulbRadius * 1.1)
                    .position(shape.bulbCentre)
                    .shadow(color: hearts > 0 ? Self.paleGold.opacity(0.8) : .clear, radius: 6)

                // Light on the glass.
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: shape.tube.width * 0.8, height: 4)
                    .position(x: shape.tube.midX + shape.tube.width * 0.05, y: shape.tube.minY + 9)
                Circle()
                    .trim(from: 0.55, to: 0.72)
                    .stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: shape.bulbRadius * 1.5, height: shape.bulbRadius * 1.5)
                    .position(shape.bulbCentre)
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement()
        .accessibilityLabel("\(hearts) of \(maxHearts) hearts")
    }

    /// A speck of gold drifting slowly through the liquid, twinkling.
    private func speck(_ index: Int, time: Double, geometry: FlaskGeometry) -> some View {
        let seed = Double(index) * 12.9898
        let drift = (time * (0.02 + 0.015 * fract(sin(seed) * 43758)) + fract(sin(seed * 1.7) * 9631))
        let x = geometry.bounds.minX + geometry.bounds.width * fract(drift)
        let y = geometry.tube.minY + geometry.tube.height * (0.2 + 0.6 * fract(sin(seed * 2.3) * 7919))
            + 4 * sin(time * 1.3 + seed)
        let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 3 + seed * 5))
        return Circle()
            .fill(Self.paleGold)
            .frame(width: 4, height: 4)
            .opacity(twinkle)
            .position(x: x, y: y)
    }

    private func fract(_ value: Double) -> Double { value - value.rounded(.down) }

    static func colour(_ value: SIMD3<Float>) -> Color { Color(uiColor: RidePalette.uiColor(value)) }
}

/// Where the flask's parts are in its frame: the bulb on the left, the tube to its right.
struct FlaskGeometry {
    let bounds: CGRect
    let bulbCentre: CGPoint
    let bulbRadius: CGFloat
    let tube: CGRect

    init(size: CGSize) {
        bounds = CGRect(origin: .zero, size: size)
        bulbRadius = size.height * 0.46
        bulbCentre = CGPoint(x: size.height * 0.56, y: size.height / 2)
        let thickness = size.height * 0.46
        tube = CGRect(x: bulbCentre.x + bulbRadius * 0.6, y: (size.height - thickness) / 2,
                      width: size.width - bulbCentre.x - bulbRadius * 0.6 - 2, height: thickness)
    }
}

/// The flask's outline, `inset` inside it: the round bulb, the flared foot behind it (two points to the left) and
/// the tube with its rounded end.
struct FlaskShape: Shape {
    let geometry: FlaskGeometry
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = geometry.bulbRadius - inset
        let centre = geometry.bulbCentre
        let bulb = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                          width: 2 * radius, height: 2 * radius))
        let tube = Path(roundedRect: geometry.tube.insetBy(dx: inset, dy: inset),
                        cornerRadius: geometry.tube.height / 2 - inset)
        // The foot: a little flare under the bulb, its two points out to the left.
        let foot = geometry.bulbRadius * 0.95 - inset
        var flare = Path()
        flare.move(to: CGPoint(x: centre.x - foot * 0.2, y: centre.y - foot * 0.75))
        flare.addLine(to: CGPoint(x: centre.x - foot * 1.12, y: centre.y - foot * 0.95))
        flare.addLine(to: CGPoint(x: centre.x - foot * 0.92, y: centre.y))
        flare.addLine(to: CGPoint(x: centre.x - foot * 1.12, y: centre.y + foot * 0.95))
        flare.addLine(to: CGPoint(x: centre.x - foot * 0.2, y: centre.y + foot * 0.75))
        flare.closeSubpath()
        return bulb.union(tube).union(flare)
    }
}

/// The liquid: the whole bulb while there is life, the tube filled to `level` (0...1), its front a wave moving
/// with `phase`.
struct LiquidShape: Shape {
    let geometry: FlaskGeometry
    var level: Double
    var phase: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set { (level, phase) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        guard level > 0.001 else { return Path() }
        let radius = geometry.bulbRadius
        let bulb = Path(ellipseIn: CGRect(x: geometry.bulbCentre.x - radius, y: geometry.bulbCentre.y - radius,
                                          width: 2 * radius, height: 2 * radius))
        let tube = geometry.tube
        let front = tube.minX + tube.width * CGFloat(min(level, 1))
        var liquid = Path()
        liquid.move(to: CGPoint(x: geometry.bounds.minX, y: tube.minY))
        let steps = 12
        for step in 0...steps {
            let y = tube.minY + tube.height * CGFloat(step) / CGFloat(steps)
            let wave = 5 * sin(Double(step) / Double(steps) * 2 * .pi + phase)
            liquid.addLine(to: CGPoint(x: front + CGFloat(wave), y: y))
        }
        liquid.addLine(to: CGPoint(x: geometry.bounds.minX, y: tube.maxY))
        liquid.closeSubpath()
        return bulb.union(liquid)
    }
}

/// A Persian eight-pointed star (khatam): two squares, one turned by 45°.
struct EightPointedStar: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.72
        var path = Path()
        for point in 0..<16 {
            let angle = Double(point) / 16 * 2 * .pi - .pi / 2
            let radius = point % 2 == 0 ? outer : inner
            let corner = CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
            if point == 0 { path.move(to: corner) } else { path.addLine(to: corner) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 24) {
        LifeFlaskView(hearts: 3, maxHearts: 3)
        LifeFlaskView(hearts: 1, maxHearts: 3)
        LifeFlaskView(hearts: 0, maxHearts: 3)
    }
    .padding()
    .background(.black)
}
#endif
