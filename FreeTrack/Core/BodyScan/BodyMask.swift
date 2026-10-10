import Foundation

/// Binary person mask, one byte per pixel (0 = background, 1 = person), row-major, same size as the analysed image.
/// Pure Swift so the width-scanning code is unit-testable with synthetic masks.
struct BodyMask: Equatable {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "mask size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(width: Int, height: Int) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height))
    }

    // MARK: - Pixel access

    @inline(__always)
    func isForeground(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return pixels[y * width + x] != 0
    }

    /// Fills an axis-aligned rectangle [x0, x1) × [y0, y1). Used by tests and previews.
    mutating func fillRect(x0: Int, x1: Int, y0: Int, y1: Int, value: UInt8 = 1) {
        let xa = max(0, min(x0, x1)), xb = min(width, max(x0, x1))
        let ya = max(0, min(y0, y1)), yb = min(height, max(y0, y1))
        guard xa < xb, ya < yb else { return }
        for y in ya..<yb {
            let row = y * width
            for x in xa..<xb { pixels[row + x] = value }
        }
    }

    mutating func fillCircle(cx: Int, cy: Int, radius: Int, value: UInt8 = 1) {
        let r2 = radius * radius
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2 {
                pixels[y * width + x] = value
            }
        }
    }

    // MARK: - Statistics

    var foregroundCount: Int { pixels.reduce(0) { $0 + Int($1) } }

    var coverage: Double { width * height > 0 ? Double(foregroundCount) / Double(width * height) : 0 }

    /// Fraction of foreground pixels that lie inside the rectangle [x0, x1] × [y0, y1] (inclusive, clamped).
    func foregroundFraction(insideX x0: Int, _ x1: Int, y y0: Int, _ y1: Int) -> Double {
        let total = foregroundCount
        guard total > 0 else { return 0 }
        var inside = 0
        for y in max(0, y0)...max(max(0, y0), min(height - 1, y1)) {
            let row = y * width
            for x in max(0, x0)...max(max(0, x0), min(width - 1, x1)) { inside += Int(pixels[row + x]) }
        }
        return Double(inside) / Double(total)
    }

    // MARK: - Scanning

    /// Highest (smallest y) foreground row among columns [x0, x1], or nil.
    func topForegroundRow(columns x0: Int, _ x1: Int) -> Int? {
        let xa = max(0, min(x0, x1)), xb = min(width - 1, max(x0, x1))
        guard xa <= xb else { return nil }
        for y in 0..<height {
            let row = y * width
            for x in xa...xb where pixels[row + x] != 0 { return y }
        }
        return nil
    }

    /// Lowest (largest y) foreground row among columns [x0, x1], or nil.
    func bottomForegroundRow(columns x0: Int, _ x1: Int) -> Int? {
        let xa = max(0, min(x0, x1)), xb = min(width - 1, max(x0, x1))
        guard xa <= xb else { return nil }
        for y in stride(from: height - 1, through: 0, by: -1) {
            let row = y * width
            for x in xa...xb where pixels[row + x] != 0 { return y }
        }
        return nil
    }

    /// Width in pixels of the contiguous foreground run on row `y` that contains `xRef`, clipped to
    /// [xMin, xMax]. Nil when `xRef` itself is background. This is FreeFit's row scan, made robust to
    /// stray blobs by requiring the run to pass through the reference column.
    func rowRunWidth(y: Int, xRef: Int, xMin: Int, xMax: Int) -> Int? {
        guard y >= 0, y < height, xRef >= 0, xRef < width, isForeground(xRef, y) else { return nil }
        let lower = max(0, xMin), upper = min(width - 1, xMax)
        var lo = xRef
        while lo - 1 >= lower, isForeground(lo - 1, y) { lo -= 1 }
        var hi = xRef
        while hi + 1 <= upper, isForeground(hi + 1, y) { hi += 1 }
        return hi - lo + 1
    }

    /// Counts foreground pixels from (x, y) inclusive stepping by (dx, dy) until background or `limit` steps.
    /// `bounded` is false when the run hit the step limit without reaching background.
    func run(fromX x: Double, y: Double, dx: Double, dy: Double, limit: Int) -> (count: Int, bounded: Bool) {
        var n = 0
        for i in 0..<max(limit, 1) {
            let xi = Int((x + dx * Double(i)).rounded()), yi = Int((y + dy * Double(i)).rounded())
            guard isForeground(xi, yi) else { return (n, true) }
            n += 1
        }
        return (n, false)
    }

    /// Width of a limb across the segment a→b, measured perpendicular to it at several fractions along its
    /// length (median of the rows that produced a value). When one side of the scan runs into another body
    /// part (arm against torso, thigh against thigh) and never reaches background within the limit, the width is
    /// taken as twice the bounded side, assuming the joint line runs through the middle of the limb.
    func limbWidth(from a: BodyPoint, to b: BodyPoint,
                   fractions: [Double] = [0.4, 0.45, 0.5, 0.55, 0.6],
                   limitFraction: Double = 0.6) -> Double? {
        let length = BodyPoint.distance(a, b)
        guard length > 1 else { return nil }
        let dx = (b.x - a.x) / length, dy = (b.y - a.y) / length
        let nx = -dy, ny = dx
        let limit = max(2, Int(length * limitFraction))
        var widths: [Double] = []
        for t in fractions {
            let px = a.x + dx * length * t, py = a.y + dy * length * t
            let side1 = run(fromX: px, y: py, dx: nx, dy: ny, limit: limit)
            let side2 = run(fromX: px, y: py, dx: -nx, dy: -ny, limit: limit)
            guard side1.count > 0, side2.count > 0 else { continue }
            switch (side1.bounded, side2.bounded) {
            case (true, true): widths.append(Double(side1.count + side2.count - 1))
            case (true, false): widths.append(Double(2 * side1.count))
            case (false, true): widths.append(Double(2 * side2.count))
            case (false, false): continue
            }
        }
        guard !widths.isEmpty else { return nil }
        let sorted = widths.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    // MARK: - Resampling

    /// Nearest-neighbour resample to a new size (used to bring a low-resolution model mask up to image size).
    func resampled(toWidth newWidth: Int, height newHeight: Int) -> BodyMask {
        guard newWidth != width || newHeight != height else { return self }
        guard newWidth > 0, newHeight > 0, width > 0, height > 0 else { return BodyMask(width: max(newWidth, 0), height: max(newHeight, 0)) }
        var out = [UInt8](repeating: 0, count: newWidth * newHeight)
        for y in 0..<newHeight {
            let sy = min(height - 1, y * height / newHeight)
            let srcRow = sy * width, dstRow = y * newWidth
            for x in 0..<newWidth {
                let sx = min(width - 1, x * width / newWidth)
                out[dstRow + x] = pixels[srcRow + sx]
            }
        }
        return BodyMask(width: newWidth, height: newHeight, pixels: out)
    }
}
