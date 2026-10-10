import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Produces a binary person mask for a photo. Joints are optional point prompts (SAM 2 uses them, Vision ignores them).
protocol BodySegmenter {
    var name: String { get }
    func segment(image: CGImage, keypoints: BodyKeypoints?) async throws -> BodyMask
}

enum BodySegmenterError: LocalizedError {
    case noResult
    case modelUnavailable
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .noResult: return "The segmentation model returned nothing."
        case .modelUnavailable: return "The segmentation model isn't installed."
        case .badOutput(let detail): return "Unexpected model output: \(detail)"
        }
    }
}

/// Always-available default: Apple's `VNGeneratePersonSegmentationRequest` at `.accurate` quality.
struct VisionPersonSegmenter: BodySegmenter {
    let name = "Apple Vision"

    func segment(image: CGImage, keypoints: BodyKeypoints?) async throws -> BodyMask {
        try await Task.detached(priority: .userInitiated) { () -> BodyMask in
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first else { throw BodySegmenterError.noResult }
            let mask = try BodyMask(pixelBuffer: observation.pixelBuffer, threshold: 128)
            return mask.resampled(toWidth: image.width, height: image.height)
        }.value
    }
}

extension BodyMask {
    /// Reads a single-channel 8-bit pixel buffer (`kCVPixelFormatType_OneComponent8`) into a binary mask.
    init(pixelBuffer: CVPixelBuffer, threshold: UInt8) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw BodySegmenterError.badOutput("empty pixel buffer")
        }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let bytesPerPixel: Int
        switch format {
        case kCVPixelFormatType_OneComponent8: bytesPerPixel = 1
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32ARGB, kCVPixelFormatType_32RGBA: bytesPerPixel = 4
        default: bytesPerPixel = 1
        }
        let src = base.assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = y * bytesPerRow
            let dst = y * width
            for x in 0..<width where src[row + x * bytesPerPixel] >= threshold {
                pixels[dst + x] = 1
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
