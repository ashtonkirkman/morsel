import CoreGraphics
import UIKit

extension BodyMask {
    /// Translucent tint image (foreground = `color` at `alpha`, background clear) for overlaying on the photo.
    func tintedImage(color: UIColor, alpha: CGFloat = 0.35) -> UIImage? {
        guard width > 0, height > 0 else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let fr = UInt8(min(max(r * 255, 0), 255)), fg = UInt8(min(max(g * 255, 0), 255)), fb = UInt8(min(max(b * 255, 0), 255))
        let fa = UInt8(min(max(alpha * 255, 0), 255))
        // Premultiplied RGBA.
        let pr = UInt8(Int(fr) * Int(fa) / 255), pg = UInt8(Int(fg) * Int(fa) / 255), pb = UInt8(Int(fb) * Int(fa) / 255)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) where pixels[i] != 0 {
            let o = i * 4
            bytes[o] = pr; bytes[o + 1] = pg; bytes[o + 2] = pb; bytes[o + 3] = fa
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo,
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
