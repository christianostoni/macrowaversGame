import SwiftUI

/// The game's name, ترنج (toranj, the citron), in the design team's lettering (`Assets/Title/toranj.svg`), written
/// above Start as by a pen: ت, then ر, ن and ج, then their dots, then the leaf grows from the fruit.
/// The letters are filled shapes: each is revealed along a hand-traced pen line (`Stroke`), thick enough to
/// cover it. With Reduce Motion the name simply fades in.
/// The pen starts once the window is in view, a moment after it opens (visionOS fades it in), and writes the name
/// again whenever the window comes back, also from the Home View.
struct ToranjTitleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// When the pen started; nil until the window is in view.
    @State private var start: Date?
    /// The name is complete: the timeline stops redrawing it.
    @State private var isWritten = false
    @State private var writing: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(paused: start == nil || isWritten || reduceMotion)) { timeline in
            let time = reduceMotion || isWritten ? Self.duration : start.map { timeline.date.timeIntervalSince($0) } ?? 0
            Canvas { context, size in
                Self.draw(in: &context, size: size, at: time)
            }
        }
        .aspectRatio(Self.viewBox.width / Self.viewBox.height, contentMode: .fit)
        .opacity(start == nil ? 0 : 1)
        .animation(reduceMotion ? .easeIn(duration: 0.8) : nil, value: start)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background {
                writing?.cancel()
                writing = nil
                start = nil
                isWritten = false
            } else if start == nil, writing == nil {
                write()
            }
        }
        // Back after the game (Restart, Digital Crown): the window shows the name anew.
        .onAppear {
            if start == nil, writing == nil, scenePhase != .background { write() }
        }
        .onDisappear {
            writing?.cancel()
            writing = nil
            start = nil
            isWritten = false
        }
        .accessibilityElement()
        .accessibilityLabel(Text("ترنج"))
        .accessibilityAddTraits(.isHeader)
    }

    /// Waits for the window to settle in view, then writes the name.
    private func write() {
        writing = Task {
            try? await Task.sleep(for: .seconds(Self.delay))
            guard !Task.isCancelled else { return }
            start = .now
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled else { return }
            isWritten = true
            writing = nil
        }
    }

    // MARK: - The drawing, `time` seconds into the writing

    /// The SVG's canvas; its shapes sit 5 units to the right in it (the group's `translate(5, 0)`).
    static let viewBox = CGSize(width: 958, height: 1118)
    static let duration: TimeInterval = 3.8
    /// How long the window takes to fade in before the pen starts.
    private static let delay: TimeInterval = 1

    static func draw(in context: inout GraphicsContext, size: CGSize, at time: TimeInterval) {
        let scale = min(size.width / viewBox.width, size.height / viewBox.height)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 5, y: 0)

        // ت and ر, one shape: the bowl from its right horn round to the left one, then the tail down to its drop.
        write(Shapes.teReh, with: Shapes.orange, along: [Stroke.te, Stroke.reh], in: context, at: time)
        // ن and ج, one shape: the stem down into the fruit, then round the fruit.
        write(Shapes.noonJim, with: Shapes.orange, along: [Stroke.noon, Stroke.jim], in: context, at: time)

        // The dots, right to left along the top, then ج's inside the fruit: each pops in.
        for (index, dot) in Shapes.dots.enumerated() {
            let grown = easeOutBack(progress(at: time, from: 2.5 + 0.15 * Double(index), length: 0.35))
            guard grown > 0 else { continue }
            var layer = context
            layer.translateBy(x: dot.x, y: dot.y)
            layer.scaleBy(x: grown, y: grown)
            let circle = Path(ellipseIn: CGRect(x: -31.5, y: -31.5, width: 63, height: 63))
            layer.fill(circle, with: gradient(Shapes.rose, in: circle.boundingRect))
        }

        // Last, the leaf unfurls from where it joins the fruit.
        let leaf = easeOutBack(progress(at: time, from: 3.2, length: 0.6))
        if leaf > 0 {
            var layer = context
            layer.translateBy(x: Shapes.leafBase.x, y: Shapes.leafBase.y)
            layer.rotate(by: .degrees(-25 * (1 - leaf)))
            layer.scaleBy(x: leaf, y: leaf)
            layer.translateBy(x: -Shapes.leafBase.x, y: -Shapes.leafBase.y)
            layer.fill(Shapes.leaf, with: gradient(Shapes.green, in: Shapes.leaf.boundingRect, radius: 0.85))
        }
    }

    /// Fills `shape` where the pen has been: each stroke in turn, over its own stretch of time.
    private static func write(_ shape: Path, with colors: [Color], along strokes: [Stroke], in context: GraphicsContext,
                              at time: TimeInterval) {
        let fill = gradient(colors, in: shape.boundingRect)
        for stroke in strokes {
            let written = easeInOut(progress(at: time, from: stroke.start, length: stroke.length))
            guard written > 0 else { continue }
            var layer = context
            layer.clip(to: stroke.line.trimmedPath(from: 0, to: written)
                .strokedPath(StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)))
            layer.fill(shape, with: fill)
        }
    }

    /// The SVG's radial gradients, light at 79 % across and 61 % down the shape, without their slight skew.
    private static func gradient(_ colors: [Color], in bounds: CGRect, radius: CGFloat = 0.71) -> GraphicsContext.Shading {
        let center = CGPoint(x: bounds.minX + 0.79 * bounds.width, y: bounds.minY + 0.615 * bounds.height)
        let endRadius = radius * sqrt((bounds.width * bounds.width + bounds.height * bounds.height) / 2)
        return .radialGradient(Gradient(colors: colors), center: center, startRadius: 0, endRadius: endRadius)
    }

    private static func progress(at time: TimeInterval, from start: TimeInterval, length: TimeInterval) -> Double {
        min(max((time - start) / length, 0), 1)
    }

    private static func easeInOut(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// Overshoots a little before settling: a dot or the leaf popping into place.
    private static func easeOutBack(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        let overshoot = 1.7
        return 1 + (overshoot + 1) * pow(x - 1, 3) + overshoot * pow(x - 1, 2)
    }
}

// MARK: - The pen

/// A pen line through a letter, in the SVG's units: thick enough to cover the letter, written in `length` s.
private struct Stroke {
    let line: Path
    let width: CGFloat
    let start: TimeInterval
    let length: TimeInterval

    /// ت: down the right horn, round the bowl's bottom, up the left horn.
    static let te = Stroke(line: Path { path in
        path.move(to: CGPoint(x: 906, y: 140))
        path.addLine(to: CGPoint(x: 906, y: 290))
        path.addQuadCurve(to: CGPoint(x: 850, y: 346), control: CGPoint(x: 906, y: 346))
        path.addLine(to: CGPoint(x: 790, y: 346))
        path.addQuadCurve(to: CGPoint(x: 711, y: 280), control: CGPoint(x: 711, y: 346))
        path.addLine(to: CGPoint(x: 711, y: 140))
    }, width: 110, start: 0, length: 0.8)

    /// ر: from the bowl down the tail to its drop.
    static let reh = Stroke(line: Path { path in
        path.move(to: CGPoint(x: 711, y: 346))
        path.addLine(to: CGPoint(x: 711, y: 430))
        path.addCurve(to: CGPoint(x: 630, y: 580), control1: CGPoint(x: 711, y: 500), control2: CGPoint(x: 680, y: 560))
        path.addLine(to: CGPoint(x: 598, y: 570))
    }, width: 140, start: 0.8, length: 0.4)

    /// ن: down the stem, then left into the top of the fruit.
    static let noon = Stroke(line: Path { path in
        path.move(to: CGPoint(x: 543, y: 120))
        path.addLine(to: CGPoint(x: 543, y: 350))
        path.addQuadCurve(to: CGPoint(x: 450, y: 438), control: CGPoint(x: 540, y: 430))
        path.addLine(to: CGPoint(x: 380, y: 440))
    }, width: 110, start: 1.25, length: 0.3)

    /// ج: round the fruit, left, down, along its bottom and up into its right lobe.
    static let jim = Stroke(line: Path { path in
        path.move(to: CGPoint(x: 380, y: 445))
        path.addCurve(to: CGPoint(x: 150, y: 700), control1: CGPoint(x: 230, y: 440), control2: CGPoint(x: 150, y: 540))
        path.addCurve(to: CGPoint(x: 420, y: 910), control1: CGPoint(x: 150, y: 850), control2: CGPoint(x: 270, y: 915))
        path.addCurve(to: CGPoint(x: 680, y: 760), control1: CGPoint(x: 580, y: 905), control2: CGPoint(x: 690, y: 850))
        path.addLine(to: CGPoint(x: 650, y: 725))
    }, width: 450, start: 1.55, length: 0.9)
}

// MARK: - The design team's shapes (from Assets/Title/toranj.svg)

private enum Shapes {
    static let orange = [Color(red: 1, green: 0.69, blue: 0.41), Color(red: 1, green: 0.43, blue: 0)]
    static let rose = [Color(red: 0.88, green: 0.32, blue: 0.49), Color(red: 1, green: 0.43, blue: 0)]
    static let green = [Color(red: 0.80, green: 0.88, blue: 0.32), Color(red: 0.11, green: 0.24, blue: 0.19)]

    /// ت's two dots, right to left, ن's, then ج's inside the fruit.
    static let dots = [CGPoint(x: 917.5, y: 31.5), CGPoint(x: 700.5, y: 31.5), CGPoint(x: 483.4, y: 31.5),
                       CGPoint(x: 451.5, y: 614.5)]
    /// Where the leaf's stalk meets the fruit.
    static let leafBase = CGPoint(x: 400, y: 395)

    static let teReh = svgPath("""
        M665.104644,408.750778 L665.104644,185.060834 C665.104644,159.028871 665.104644,146.012889 670.162149,136.0662 \
        C678.083592,120.486952 694.061754,110.655224 711.539163,110.60598 C728.874599,110.557135 744.727553,120.375703 \
        752.406882,135.917505 C757.308717,145.838077 757.066152,158.737691 756.581023,184.536918 L755.865278,222.600358 \
        C755.307674,252.253856 755.028871,267.080605 760.653096,278.487455 C769.463912,296.357234 787.658739,307.672403 \
        807.582581,307.672403 C827.631845,307.672403 845.986198,296.424842 855.088373,278.560816 C860.899578,267.155684 \
        860.899578,252.225525 860.899578,222.365207 L860.899578,183.623762 C860.899578,158.019346 860.899578,145.217137 \
        865.882529,135.437545 C873.687399,120.119626 889.425761,110.475145 906.617464,110.475145 C923.620011,110.475145 \
        939.118098,120.219443 946.486435,135.54244 C951.189269,145.322329 950.773442,157.965765 949.941788,183.252637 \
        L946.527025,287.080324 C945.386115,321.77028 944.815661,339.115258 937.761581,352.205926 C929.861195,366.867134 \
        916.502192,377.825042 900.578982,382.705467 C891.510471,385.484944 880.547624,385.484944 858.62193,385.484944 \
        C836.736483,385.484944 825.793759,385.484944 816.779357,388.22892 C800.671492,393.132138 787.180096,404.249582 \
        779.288327,419.12321 C772.274263,432.342628 774.556968,449.072223 767.868325,480.10584 C762.94571,502.945533 \
        753.584336,527.602676 739.784202,554.077266 C728.891122,574.974879 715.331379,592.317774 699.104972,606.10595 \
        C660.515527,638.896823 629.703739,641.738575 607.425406,636.647467 C572.402888,628.644021 547.563839,597.491347 \
        547.563839,561.565981 L547.563839,561.553825 C547.563839,529.095828 573.876244,502.783422 606.334241,502.783422 \
        C628.434198,502.783422 648.665883,490.38543 658.699053,470.694224 C665.104644,458.122545 665.104644,441.665289 \
        665.104644,408.750778 Z
        """)

    static let noonJim = svgPath("""
        M546.335544,87.8633211 C562.960456,87.8633211 578.179942,97.1898339 585.727494,112.002739 C590.546163,121.459909 \
        590.546163,133.840043 590.546163,158.600311 L590.546163,358.835144 C590.546163,392.259106 590.546163,408.971087 \
        584.785649,422.042575 C579.706471,433.568008 571.518864,443.451799 561.139867,450.586929 C549.368601,458.679186 \
        532.948504,461.788966 500.108311,468.008526 L434.060478,480.517236 C304.338684,505.085071 293.531031,686.684555 \
        419.42092,726.47222 C419.430622,726.475286 419.440325,726.478352 419.450027,726.481418 C474.75605,743.958735 \
        519.9513,747.022676 555.035777,735.673241 C593.120703,723.353194 607.413769,702.511372 627.808907,700.297079 \
        C645.6416,698.360989 663.514873,703.565288 677.519112,714.773978 C693.535035,727.592776 704.970429,751.808293 \
        713.302948,802.623279 C731.111484,911.226749 690.192555,995.919475 590.546163,1056.70146 C365.076959,1194.23244 \
        139.064787,1078.0338 46.3549291,919.170484 C38.9658013,906.508816 32.4600618,893.010868 26.8377108,878.676638 \
        C-30.211927,733.228118 1.23210891,636.982123 31.6488871,575.884877 C69.2450934,500.366534 136.761205,444.054041 \
        217.801016,420.622356 C248.537835,411.735175 282.579893,409.348239 350.664007,404.574367 L383.981201,402.238256 \
        C418.384635,399.825982 435.586352,398.619844 448.542713,391.572201 C459.960618,385.361405 469.353827,376.001069 \
        475.604614,364.605008 C482.697636,351.673434 483.964072,334.476051 486.496943,300.081286 L496.879226,159.096556 \
        C498.743995,133.774185 499.67638,121.113 505.10332,111.693611 C513.59811,96.9494393 529.319315,87.8633211 \
        546.335544,87.8633211 Z
        """)

    static let leaf = svgPath("""
        M163.394648,220.811076 C248.158913,223.154458 306.760286,231.770449 339.198768,246.659047 C381.765705,266.196398 \
        405.816607,308.714193 411.351475,374.21243 C411.770254,379.168156 411.229184,384.158133 409.757967,388.908934 \
        L404.715271,405.192633 C399.511302,421.99711 383.626747,433.176288 366.052131,432.398712 C318.917868,430.313291 \
        284.239465,424.738512 262.016922,415.674377 C221.972839,399.341189 156.375468,303.942111 135.707745,281.269549 \
        C135.705222,281.266782 135.702698,281.264014 135.700175,281.261246 C114.232656,257.715447 131.543689,219.930529 \
        163.394648,220.811076 Z
        """)

    /// The absolute `M`, `L`, `C` and `Z` commands Sketch exports.
    private static func svgPath(_ data: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        func point(_ index: Int) -> CGPoint { CGPoint(x: numbers[index], y: numbers[index + 1]) }
        func flush() {
            switch command {
            case "M" where numbers.count >= 2: path.move(to: point(0))
            case "L" where numbers.count >= 2: path.addLine(to: point(0))
            case "C" where numbers.count >= 6: path.addCurve(to: point(4), control1: point(0), control2: point(2))
            default: break
            }
            numbers.removeAll()
        }
        for token in data.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }) {
            if let first = token.first, first.isLetter {
                flush()
                command = first
                if command == "Z" { path.closeSubpath() }
                if let number = Double(token.dropFirst()) { numbers.append(number) }
            } else if let number = Double(token) {
                numbers.append(number)
            }
        }
        flush()
        return path
    }
}

#Preview {
    ToranjTitleView()
        .frame(height: 240)
        .padding()
}
