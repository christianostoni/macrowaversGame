// Builds the story scroll's page (the texture on the front of its paper): the paper with its ornamental border
// (`paper.png`), made as long as the story needs, with the chapter's story in Persian Nastaliq and the painting
// (`painting.png`) at its end. Both images are 1024 x 1536 px, made with ChatGPT in the game's low-poly airbrush
// style, without any text: image models cannot write Persian, so the text is set here with a real font (Noto
// Nastaliq Urdu, which comes with macOS).
//
// The paper is lengthened without stretching its border: its header (rows 0..<headerEnd) stays at the top, the
// rest of it at the bottom, and between them its band of side borders and plain paper is repeated, one period of
// the border's pattern (`borderPeriod` rows) at a time, so every join is seamless.
//
// Usage, from the repository's root: swift Assets/Scroll/make_scroll_page.swift
// It writes Sources/Macrowavers/Resources/ScrollPage.jpg. The app reads the page's proportions from the image:
// a longer story makes a longer scroll. See docs/features/storytelling/README.md.
import AppKit
import simd

let folder = "Assets/Scroll"
let output = "Sources/Macrowavers/Resources/ScrollPage.jpg"
/// Width of the page (px): the paper is 1024 px wide, drawn 1.5 times larger.
let width: CGFloat = 1536
let scale = width / 1024

// The paper (rows and columns in paper.png's pixels, measured on it).
/// Below the header (the band with the cartouche): from here the paper is the side borders and plain paper.
let headerEnd: CGFloat = 200
/// The side borders' pattern repeats every this many rows.
let borderPeriod: CGFloat = 216
/// The plain paper ends here: the footer's band begins.
let footerStart: CGFloat = 1438
/// The cartouche's centre, where the title goes, and the room inside it.
let cartoucheCentre = CGPoint(x: 512, y: 96)
let cartoucheRoom = CGSize(width: 240, height: 84)
/// The plain paper between the side borders.
let paperLeft: CGFloat = 96
let paperRight: CGFloat = 926

// The page (px of the page).
/// Between the side borders and the text.
let textInset: CGFloat = 96
let gap: CGFloat = 72
let bodySize: CGFloat = 50
let proverbSize: CGFloat = 66
let titleSize: CGFloat = 76

let title = "درخت شاه"
/// The story, one string a paragraph (`\u{200C}` is the half-space, the zero-width non-joiner).
let paragraphs = [
    """
    یکی بود، یکی نبود. روزگاری شاهی بر جزیره\u{200C}ای شناور میان زمین و آسمان درختی کاشت. \
    میوه\u{200C}هایش نور ستارگان فروافتاده را در خود داشت و تنها دست کسی از خاندان شاه \
    می\u{200C}توانست آن را بچیند. شاه نگهبانی درخت را به دوستی دیرین سپرد: اژدهایی از آسمان.
    """,
    """
    اما دیو سیاه آن نور را می\u{200C}خواست. چون نتوانست میوه\u{200C}ها را برباید، نگهبانشان را \
    نفرین کرد: «تا ابد گرد این درخت بچرخ، تا ابد از آن پاسداری کن، و هرگز به میوه\u{200C}ای \
    دست نزن.» کرم\u{200C}هایش را در میوه\u{200C}ها نهاد و خاندان شاه را چنان از میان برد که \
    جهان نامشان را از یاد برد. هر بار که اژدها گرد درخت می\u{200C}چرخد، تنش \
    گره\u{200C}خورده\u{200C}تر و دلش خشمگین\u{200C}تر می\u{200C}شود.
    """,
    """
    تنها اکسیری که از میوه\u{200C}های همین درخت ساخته شود نفرین را نرم می\u{200C}کند، و تنها \
    دستی شکیبا گره\u{200C}هایش را می\u{200C}گشاید. اما کسی از خاندان شاه نمانده بود که \
    میوه\u{200C}ها را بچیند.
    """,
    """
    دیو چنین می\u{200C}پنداشت. یکی از فرزندان شاه زنده ماند و خود هرگز ندانست. درخت تو را به \
    یاد دارد.
    """,
]
let proverb = "صبر تلخ است، ولیکن بَرِ شیرین دارد"

// The game's colours: deep indigo ink, the border's violet and pink, its gold.
let ink = NSColor(srgbRed: 0.17, green: 0.11, blue: 0.32, alpha: 1)
let pink = NSColor(srgbRed: 0.80, green: 0.25, blue: 0.45, alpha: 1)
let violet = NSColor(srgbRed: 0.36, green: 0.22, blue: 0.66, alpha: 1)
let gold = NSColor(srgbRed: 0.85, green: 0.64, blue: 0.27, alpha: 1)

func image(_ name: String) -> CGImage {
    let url = URL(fileURLWithPath: "\(folder)/\(name)")
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data), let image = rep.cgImage else {
        fatalError("Missing \(url.path): run from the repository's root")
    }
    return image
}

func nastaliq(_ size: CGFloat) -> NSFont {
    guard let font = NSFont(name: "NotoNastaliqUrdu", size: size) else { fatalError("Noto Nastaliq Urdu is not installed") }
    return font
}

func style(_ alignment: NSTextAlignment, lineSpacing: CGFloat, after: CGFloat) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.baseWritingDirection = .rightToLeft
    style.lineSpacing = lineSpacing
    style.paragraphSpacing = after
    return style
}

let paper = image("paper.png")
let painting = image("painting.png")

// The story, set right to left, justified (the last line of each paragraph to the right), then the proverb in pink.
let story = NSMutableAttributedString()
for paragraph in paragraphs {
    story.append(NSAttributedString(string: paragraph + "\n", attributes: [
        .font: nastaliq(bodySize), .foregroundColor: ink,
        .paragraphStyle: style(.justified, lineSpacing: bodySize * 0.5, after: bodySize * 0.9),
    ]))
}
story.append(NSAttributedString(string: proverb, attributes: [
    .font: nastaliq(proverbSize), .foregroundColor: pink,
    .paragraphStyle: style(.center, lineSpacing: 0, after: 0),
]))
let textLeft = paperLeft * scale + textInset
let textWidth = (paperRight - paperLeft) * scale - 2 * textInset
let textHeight = ceil(story.boundingRect(with: NSSize(width: textWidth, height: 100_000),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
/// Narrower than the text: at the end of the scroll the whole painting fits between the rolls.
let paintingWidth = (textWidth * 0.85).rounded()
let paintingHeight = paintingWidth * CGFloat(painting.height) / CGFloat(painting.width)

// From the top of the page.
let textTop = headerEnd * scale + gap * 0.6
let contentEnd = textTop + textHeight + gap + paintingHeight + gap * 0.8

// The paper's length: the band repeated `extraPeriods` more times, enough for the text and the painting.
let paperHeight = CGFloat(paper.height)
let neededRows = ceil(contentEnd / scale) + (paperHeight - footerStart)
let extraPeriods = max(0, Int(ceil((neededRows - paperHeight) / borderPeriod)))
let rows = paperHeight + CGFloat(extraPeriods) * borderPeriod
let height = (rows * scale).rounded()
// The painting at the end of the plain paper (whatever the repeats left over goes above it).
let paintingTop = (rows - (paperHeight - footerStart)) * scale - gap * 0.8 - paintingHeight

guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("No context") }
context.interpolationQuality = .high

/// Draws rows `from..<to` of the paper at `top` (page px from the top). On whole pixels, one more at the bottom that
/// the next piece covers: a piece ending on half a pixel left a dark line at the join.
func drawPaper(rows from: CGFloat, to: CGFloat, at top: CGFloat) {
    guard let strip = paper.cropping(to: CGRect(x: 0, y: from, width: CGFloat(paper.width), height: to - from)) else { return }
    let pieceTop = top.rounded(), pieceBottom = (top + (to - from) * scale).rounded() + 1
    let rect = CGRect(x: 0, y: height - pieceBottom, width: width, height: pieceBottom - pieceTop)
    context.draw(strip, in: rect)
}

// The header and one period of the band, the period again `extraPeriods` times, then the rest of the paper.
var top: CGFloat = 0
drawPaper(rows: 0, to: headerEnd + borderPeriod, at: top)
top += (headerEnd + borderPeriod) * scale
for _ in 0..<extraPeriods {
    drawPaper(rows: headerEnd, to: headerEnd + borderPeriod, at: top)
    top += borderPeriod * scale
}
drawPaper(rows: headerEnd + borderPeriod, to: paperHeight, at: top)

// The paper's airbrush gradient goes on along its band: each repeat started a little darker than the last one ended,
// a line at every join. Each row of the band is brought to the average of the rows around it, one border period
// (the gradient's steps) wide: the steps go, the paper's soft gradient stays.
if let data = context.data {
    let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * Int(height))
    let rowBytes = context.bytesPerRow
    let bandTop = Int(headerEnd * scale), bandBottom = Int((rows - (paperHeight - footerStart)) * scale)
    let left = Int(paperLeft * scale) + 24, right = Int(paperRight * scale) - 24
    func mean(row: Int) -> SIMD3<Float> {
        var sum = SIMD3<Float>.zero
        for column in stride(from: left, to: right, by: 2) {
            let index = row * rowBytes + column * 4
            sum += SIMD3(Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]))
        }
        return sum / Float((right - left) / 2)
    }
    let means = (bandTop..<bandBottom).map(mean(row:))
    var sums = [SIMD3<Float>.zero]
    for value in means { sums.append(sums[sums.count - 1] + value) }
    let reach = Int(borderPeriod * scale) / 2
    for (offset, row) in (bandTop..<bandBottom).enumerated() {
        let low = max(0, offset - reach), high = min(means.count, offset + reach)
        let gain = (sums[high] - sums[low]) / Float(high - low) / simd_max(means[offset], SIMD3(repeating: 1))
        for column in 0..<Int(width) {
            let index = row * rowBytes + column * 4
            for channel in 0..<3 {
                pixels[index + channel] = UInt8(clamping: Int((Float(pixels[index + channel]) * gain[channel]).rounded()))
            }
        }
    }
}

// Text, drawn through AppKit (Core Text shapes the Nastaliq) in the page's top-down coordinates.
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
context.translateBy(x: 0, y: height)
context.scaleBy(x: 1, y: -1)

let titleText = NSAttributedString(string: title, attributes: [
    .font: nastaliq(titleSize), .foregroundColor: violet, .paragraphStyle: style(.center, lineSpacing: 0, after: 0),
])
let titleBox = titleText.boundingRect(with: NSSize(width: cartoucheRoom.width * scale, height: 1000),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading])
titleText.draw(with: CGRect(x: (cartoucheCentre.x - cartoucheRoom.width / 2) * scale,
                            y: cartoucheCentre.y * scale - titleBox.height / 2,
                            width: cartoucheRoom.width * scale, height: titleBox.height),
               options: [.usesLineFragmentOrigin, .usesFontLeading])

story.draw(with: CGRect(x: textLeft, y: textTop, width: textWidth, height: textHeight),
           options: [.usesLineFragmentOrigin, .usesFontLeading])

// The painting, framed in gold, the right way up in the flipped context.
let paintingRect = CGRect(x: textLeft + (textWidth - paintingWidth) / 2, y: paintingTop, width: paintingWidth,
                          height: paintingHeight)
context.saveGState()
context.translateBy(x: 0, y: paintingRect.maxY)
context.scaleBy(x: 1, y: -1)
context.draw(painting, in: CGRect(x: paintingRect.minX, y: 0, width: paintingRect.width, height: paintingRect.height))
context.restoreGState()
gold.setStroke()
let frame = NSBezierPath(rect: paintingRect.insetBy(dx: -6, dy: -6))
frame.lineWidth = 4
frame.stroke()

guard let page = context.makeImage(),
      let jpeg = NSBitmapImageRep(cgImage: page).representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
    fatalError("Could not encode the page")
}
try jpeg.write(to: URL(fileURLWithPath: output))
print("\(output): \(Int(width)) x \(Int(height)) px, the border's band \(extraPeriods) times more")
