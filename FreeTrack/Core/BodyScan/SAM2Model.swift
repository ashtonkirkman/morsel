import CoreGraphics
import CoreML
import Foundation
import Vision

/// Thin wrapper around Apple's Core ML conversion of Meta's Segment Anything 2.1
/// (Hugging Face `apple/coreml-sam2.1-tiny` / `apple/coreml-sam2.1-small`). Everything model-specific lives here.
///
/// Verified against the Hugging Face file listings, the `model.mlmodel` specs and the `huggingface/sam2-studio`
/// sample (`SAM2.swift`) plus the `coreml/export.py` conversion script on the `coreml-conversion` branch:
///
/// - Image encoder `SAM2_1<Variant>ImageEncoderFLOAT16.mlpackage`
///   input  `image`           RGB image 1024×1024 (ImageNet normalisation is baked into the model)
///   output `image_embedding` [1, 256, 64, 64], `feats_s0` [1, 32, 256, 256], `feats_s1` [1, 64, 128, 128]
/// - Prompt encoder `SAM2_1<Variant>PromptEncoderFLOAT16.mlpackage`
///   input  `points` float32 [1, N, 2] in 1024×1024 pixel space (x, y), N = 1…16
///          `labels` int32   [1, N]    1 = foreground, 0 = background (2/3 = box corners, unused here)
///   output `sparse_embeddings` [1, N+1, 256] (a padding point is appended), `dense_embeddings` [1, 256, 64, 64]
/// - Mask decoder `SAM2_1<Variant>MaskDecoderFLOAT16.mlpackage`
///   input  `image_embedding`, `sparse_embedding` (enumerated shapes [1, 2…15, 256] → at most 14 points),
///          `dense_embedding`, `feats_s0`, `feats_s1`
///   output `low_res_masks` [1, 3, 256, 256] logits (> 0 = foreground), `scores` [1, 3] predicted IoU
///
/// The image is squashed (not letterboxed) to 1024×1024 at export time, so the mask and the point prompts map
/// to the original image by plain proportional scaling.
final class SAM2Model {
    enum Variant: String, CaseIterable, Codable {
        case tiny, small

        var repository: String { "apple/coreml-sam2.1-\(rawValue)" }
        var packagePrefix: String { rawValue == "tiny" ? "SAM2_1Tiny" : "SAM2_1Small" }
        var imageEncoderName: String { packagePrefix + "ImageEncoderFLOAT16" }
        var promptEncoderName: String { packagePrefix + "PromptEncoderFLOAT16" }
        var maskDecoderName: String { packagePrefix + "MaskDecoderFLOAT16" }
        var packageNames: [String] { [imageEncoderName, promptEncoderName, maskDecoderName] }

        /// Weight sizes read from the Hugging Face tree (`weights/weight.bin` per package), rounded up for the specs.
        var approximateBytes: Int64 {
            switch self {
            case .tiny: return 80_000_000
            case .small: return 94_000_000
            }
        }
    }

    struct PointPrompt {
        var x: Double
        var y: Double
        var isForeground: Bool
    }

    static let inputSide = 1024
    static let maskSide = 256
    /// Decoder accepts sparse embeddings of 2…15 tokens; the prompt encoder adds one padding token.
    static let maxPoints = 14

    let variant: Variant
    private let imageEncoder: MLModel
    private let promptEncoder: MLModel
    private let maskDecoder: MLModel
    private let imageConstraint: MLImageConstraint

    /// Loads the three compiled models (`.mlmodelc` directories) from `directory`.
    init(variant: Variant, directory: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.variant = variant
        imageEncoder = try MLModel(contentsOf: directory.appendingPathComponent(variant.imageEncoderName + ".mlmodelc"), configuration: config)
        promptEncoder = try MLModel(contentsOf: directory.appendingPathComponent(variant.promptEncoderName + ".mlmodelc"), configuration: config)
        maskDecoder = try MLModel(contentsOf: directory.appendingPathComponent(variant.maskDecoderName + ".mlmodelc"), configuration: config)
        guard let constraint = imageEncoder.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            // VERIFY: the encoder's image input is named "image" (confirmed in model.mlmodel and sam2-studio).
            throw BodySegmenterError.badOutput("image encoder has no 'image' input")
        }
        imageConstraint = constraint
    }

    /// Runs encoder → prompt encoder → decoder and returns the best mask at the image's size.
    func segment(image: CGImage, prompts: [PointPrompt]) throws -> BodyMask {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { throw BodySegmenterError.badOutput("empty image") }
        let usable = Array(prompts.prefix(Self.maxPoints))
        guard !usable.isEmpty else { throw BodySegmenterError.badOutput("no point prompts") }

        // 1. Image encoder. `.scaleFill` squashes to 1024×1024 like the exporter's PIL resize.
        let imageValue = try MLFeatureValue(cgImage: image, constraint: imageConstraint,
                                            options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let encoderOut = try imageEncoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": imageValue]))
        guard let embedding = encoderOut.featureValue(for: "image_embedding")?.multiArrayValue,
              let feats0 = encoderOut.featureValue(for: "feats_s0")?.multiArrayValue,
              let feats1 = encoderOut.featureValue(for: "feats_s1")?.multiArrayValue else {
            throw BodySegmenterError.badOutput("image encoder outputs missing")
        }

        // 2. Prompt encoder. Coordinates are scaled into the 1024×1024 input space.
        let points = try MLMultiArray(shape: [1, NSNumber(value: usable.count), 2], dataType: .float32)
        let labels = try MLMultiArray(shape: [1, NSNumber(value: usable.count)], dataType: .int32)
        for (i, p) in usable.enumerated() {
            let sx = p.x / Double(width) * Double(Self.inputSide)
            let sy = p.y / Double(height) * Double(Self.inputSide)
            points[[0, NSNumber(value: i), 0]] = NSNumber(value: Float(sx))
            points[[0, NSNumber(value: i), 1]] = NSNumber(value: Float(sy))
            labels[[0, NSNumber(value: i)]] = NSNumber(value: Int32(p.isForeground ? 1 : 0))
        }
        let promptOut = try promptEncoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["points": points, "labels": labels]))
        guard let sparse = promptOut.featureValue(for: "sparse_embeddings")?.multiArrayValue,
              let dense = promptOut.featureValue(for: "dense_embeddings")?.multiArrayValue else {
            throw BodySegmenterError.badOutput("prompt encoder outputs missing")
        }

        // 3. Mask decoder.
        let decoderOut = try maskDecoder.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "image_embedding": embedding,
            "sparse_embedding": sparse,
            "dense_embedding": dense,
            "feats_s0": feats0,
            "feats_s1": feats1
        ]))
        guard let masks = decoderOut.featureValue(for: "low_res_masks")?.multiArrayValue,
              let scores = decoderOut.featureValue(for: "scores")?.multiArrayValue else {
            throw BodySegmenterError.badOutput("mask decoder outputs missing")
        }

        // 4. Best of the three candidate masks by predicted IoU, upscaled with bilinear interpolation, thresholded at 0.
        let maskCount = masks.shape.count >= 2 ? masks.shape[1].intValue : 1
        var best = 0
        var bestScore = -Float.infinity
        for k in 0..<max(maskCount, 1) {
            let s = scores.count > k ? scores[k].floatValue : 0
            if s > bestScore { bestScore = s; best = k }
        }
        let logits = Self.plane(from: masks, index: best)
        return Self.upscaledMask(logits: logits.values, side: logits.side, toWidth: width, height: height)
    }

    // MARK: - Helpers

    /// Copies mask `index` out of a [1, K, S, S] array as Float values.
    private static func plane(from array: MLMultiArray, index: Int) -> (values: [Float], side: Int) {
        let dims = array.shape.map(\.intValue)
        let side = dims.count >= 2 ? dims[dims.count - 1] : maskSide
        let rows = dims.count >= 2 ? dims[dims.count - 2] : maskSide
        let planeSize = side * rows
        var values = [Float](repeating: 0, count: planeSize)
        let offset = index * planeSize
        if array.dataType == .float32 {
            // VERIFY: the decoder outputs are float32 (coremltools default for outputs without an explicit dtype).
            array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                guard buffer.count >= offset + planeSize else { return }
                for i in 0..<planeSize { values[i] = buffer[offset + i] }
            }
        } else {
            // Generic (slower) path for float16 / double outputs.
            for i in 0..<planeSize { values[i] = array[offset + i].floatValue }
        }
        return (values, side)
    }

    /// Bilinear upscale of square logits to width×height, thresholded at 0.
    static func upscaledMask(logits: [Float], side: Int, toWidth width: Int, height: Int) -> BodyMask {
        guard side > 1, logits.count >= side * side, width > 0, height > 0 else { return BodyMask(width: max(width, 0), height: max(height, 0)) }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let scaleX = Float(side) / Float(width), scaleY = Float(side) / Float(height)
        for y in 0..<height {
            let fy = min(max((Float(y) + 0.5) * scaleY - 0.5, 0), Float(side - 1))
            let y0 = Int(fy), y1 = min(y0 + 1, side - 1)
            let wy = fy - Float(y0)
            let row0 = y0 * side, row1 = y1 * side
            let dst = y * width
            for x in 0..<width {
                let fx = min(max((Float(x) + 0.5) * scaleX - 0.5, 0), Float(side - 1))
                let x0 = Int(fx), x1 = min(x0 + 1, side - 1)
                let wx = fx - Float(x0)
                let top = logits[row0 + x0] * (1 - wx) + logits[row0 + x1] * wx
                let bottom = logits[row1 + x0] * (1 - wx) + logits[row1 + x1] * wx
                if top * (1 - wy) + bottom * wy > 0 { pixels[dst + x] = 1 }
            }
        }
        return BodyMask(width: width, height: height, pixels: pixels)
    }
}
