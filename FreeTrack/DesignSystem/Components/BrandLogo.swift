import SwiftUI

// MARK: - Brand mark geometry
// The app icon as vector geometry so it can be drawn in-app at any size. These numbers are
// the SAME design-space constants as `Mark` in scripts/make_icon.py (a 1024 x 1024 canvas);
// when one changes, change the other.
//
// "The ring that lets go": the calorie ring opened at about 1:30, with a check mark inside
// whose long leg climbs up and out through the opening. One stroke weight everywhere.

enum BrandMark {
    static let canvas: CGFloat = 1024
    static let cx: CGFloat = 512
    static let cy: CGFloat = 512 + 22
    static let r: CGFloat = 308
    static let stroke: CGFloat = 0.27 * r
    /// Degrees clockwise from 12 o'clock.
    static let gapCenter: CGFloat = 43.5
    static let gapHalf: CGFloat = 28
    static let p0 = CGPoint(x: -0.62 * r, y: 0.02 * r)
    static let vertex = CGPoint(x: -0.20 * r, y: 0.44 * r)
    static let p2 = CGPoint(x: 0.98 * r, y: -1.14 * r)
}

/// The Free Track mark as a stroke-able `Shape`. Stroke it with round caps and joins and a
/// line width of `BrandMark.stroke / BrandMark.canvas * side`.
struct BrandMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let s = side / BrandMark.canvas
        let ox = rect.minX + (rect.width - side) / 2
        let oy = rect.minY + (rect.height - side) / 2

        func point(_ offset: CGPoint) -> CGPoint {
            CGPoint(x: ox + (BrandMark.cx + offset.x) * s,
                    y: oy + (BrandMark.cy + offset.y) * s)
        }

        var path = Path()

        // Ring. SwiftUI measures angles from 3 o'clock; because the y axis points down,
        // increasing angles sweep clockwise on screen and `clockwise: false` follows the
        // increasing direction. Start just past the gap, sweep round to just before it.
        let start = Angle.degrees(Double(BrandMark.gapCenter + BrandMark.gapHalf - 90))
        let end = Angle.degrees(Double(BrandMark.gapCenter - BrandMark.gapHalf + 270))
        path.addArc(center: point(.zero), radius: BrandMark.r * s,
                    startAngle: start, endAngle: end, clockwise: false)

        // Check: short leg down into the vertex, long leg up and out through the gap.
        path.move(to: point(BrandMark.p0))
        path.addLine(to: point(BrandMark.vertex))
        path.addLine(to: point(BrandMark.p2))

        return path
    }
}

// MARK: - BrandLogo

/// The brand mark, drawn as vectors (no image asset) so it is crisp at any size.
///
/// - `.tile`: the app icon as it appears on the home screen: white mark on the accent tile
///   in light mode; in dark mode it mirrors the iOS 18 dark icon (accent mark on a dark tile).
/// - `.mark`: just the mark, accent-tinted, for use directly on `Color.mBackground`.
///
/// ```swift
/// BrandLogo(size: 96)                 // tile
/// BrandLogo(size: 28, style: .mark)   // inline mark
/// ```
struct BrandLogo: View {
    enum Style { case mark, tile }

    var size: CGFloat = 96
    var style: Style = .tile

    @Environment(\.colorScheme) private var colorScheme

    private var cornerRadius: CGFloat { size * 0.2237 }   // iOS icon corner ratio
    private var lineWidth: CGFloat { size * BrandMark.stroke / BrandMark.canvas }

    private var markColor: Color {
        switch style {
        case .mark: return .mAccent
        case .tile: return colorScheme == .dark ? .mAccent : .white
        }
    }

    var body: some View {
        ZStack {
            if style == .tile {
                let tile = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                tile.fill(colorScheme == .dark ? Color.mSurfaceElevated : Color.mAccent)
                // The same barely-there radial lift the icon tile has, top-left.
                tile.fill(
                    RadialGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.05 : 0.12), .clear],
                        center: UnitPoint(x: 0.30, y: 0.25),
                        startRadius: 0,
                        endRadius: size * 0.95
                    )
                )
            }
            BrandMarkShape()
                .stroke(markColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Free Track")
        .accessibilityAddTraits(.isImage)
    }
}

#Preview("BrandLogo") {
    VStack(spacing: Spacing.l) {
        BrandLogo(size: 120)
        BrandLogo(size: 60)
        BrandLogo(size: 96, style: .mark)
        HStack(spacing: Spacing.s) {
            BrandLogo(size: 28, style: .mark)
            Text("Free Track").font(FreeTrackFont.title)
        }
    }
    .padding(Spacing.xl)
    .background(Color.mBackground)
}
